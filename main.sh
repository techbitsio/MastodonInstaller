#!/bin/bash

staging=false

user_check() {
	if [ "$username" == "mastodon" ]; then
          echo 'mastodon is reserved for running Mastodon. Create a different user for server administration.'
          echo 'Quitting...'
          exit 1
	fi
}

## Check if rsync is installed. Install if required (Debian 10/11 - not installed by default?)
type -p rsync >/dev/null || apt-get install rsync -y

while getopts ":e:d:u:s" flag; do
    case ${flag} in
        e  ) email=${OPTARG}    
             ;;
	d  ) domain=${OPTARG}
	     ;;
     	u  ) username=${OPTARG}
	     user_check
	     ;;
	s  ) staging=true
             ;;
    esac
done

if [ -z "$username" ]; then
	echo "New username:"
	read username
	user_check
else
	echo "Adding user: $username"
fi

adduser --gecos "" $username
usermod -aG sudo $username
rsync --archive --chown=$username:$username ~/.ssh /home/$username

if [ -z "$domain" ]; then
	echo "Domain (e.g. domain.com or sub.domain.com) ="
	read domain
fi

if [ -z "$email" ]; then
    echo "Enter email address:"
    read email
fi

if [ $(awk -F= '/^ID=/{print $2}' /etc/os-release) == "debian" ]; then
    # Debian Specific Tasks
    echo ' ' >/dev/null
fi

# This is messy. There's another check for Ubuntu 22.04 at the end, but still... find a better way.
ur=0
if [ $(awk -F= '/^ID=/{print $2}' /etc/os-release) == "ubuntu" ]; then
    ur=$(cat /etc/lsb-release | grep DISTRIB_RELEASE | sed 's/DISTRIB_RELEASE=//')
fi

if [ "$ur" = "22.04" ]; then
    sed -i 's/#$nrconf{kernelhints} = -1;/$nrconf{kernelhints} = 0;/' /etc/needrestart/needrestart.conf
    sed -i 's/#$nrconf{restart} = '\''i'\'';/$nrconf{restart} = '\''a'\'';/' /etc/needrestart/needrestart.conf
    sed -i 's/#$nrconf{ucodehints} = 0;/$nrconf{ucodehints} = 0;/' /etc/needrestart/needrestart.conf

    snap install core
    snap refresh core
    snap install --classic certbot
    ln -s /snap/bin/certbot /usr/bin/certbot
fi


apt-get update

DEBIAN_FRONTEND=noninteractive \
	apt-get \
	-o Dpkg::Options::="--force-confnew" \
	--allow-downgrades --allow-remove-essential --allow-change-held-packages \
	-fuy \
	dist-upgrade

## Fail2ban install & config file
apt-get install fail2ban -y

touch /etc/fail2ban/jail.local

tee -a /etc/fail2ban/jail.local > /dev/null <<EOL
[DEFAULT]
destemail = $email
sendername = Fail2Ban

[sshd]
enabled = true
port = 22

[sshd-ddos]
enabled = true
port = 22
EOL

## IPtables install & config & apply

echo iptables-persistent iptables-persistent/autosave_v4 boolean false | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | sudo debconf-set-selections
apt-get -y install iptables-persistent

touch /etc/iptables/rules.v4

tee -a /etc/iptables/rules.v4 > /dev/null <<EOL
*filter

#  Allow all loopback (lo0) traffic and drop all traffic to 127/8 that doesn't use lo0
-A INPUT -i lo -j ACCEPT
-A INPUT ! -i lo -d 127.0.0.0/8 -j REJECT

#  Accept all established inbound connections
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

#  Allow all outbound traffic - you can modify this to only allow certain traffic
-A OUTPUT -j ACCEPT

#  Allow HTTP and HTTPS connections from anywhere (the normal ports for websites and SSL).
-A INPUT -p tcp --dport 80 -j ACCEPT
-A INPUT -p tcp --dport 443 -j ACCEPT

#  Allow SSH connections
#  The -dport number should be the same port number you set in sshd_config
-A INPUT -p tcp -m state --state NEW --dport 22 -j ACCEPT

#  Allow ping
-A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT

#  Log iptables denied calls
-A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables denied: " --log-level 7

#  Reject all other inbound - default deny unless explicitly allowed policy
-A INPUT -j REJECT
-A FORWARD -j REJECT

COMMIT
EOL

iptables-restore < /etc/iptables/rules.v4


apt install -y curl wget gnupg apt-transport-https lsb-release ca-certificates

curl -sL https://deb.nodesource.com/setup_16.x | bash -
wget -O /usr/share/keyrings/postgresql.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc
echo "deb [signed-by=/usr/share/keyrings/postgresql.asc] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/postgresql.list

apt-get update

apt-get install -y \
  imagemagick ffmpeg libpq-dev libxml2-dev libxslt1-dev file git-core \
  g++ libprotobuf-dev protobuf-compiler pkg-config nodejs gcc autoconf \
  bison build-essential libssl-dev libyaml-dev libreadline6-dev \
  zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev \
  nginx redis-server redis-tools postgresql postgresql-contrib \
  certbot python3-certbot-nginx libidn11-dev libicu-dev libjemalloc-dev sudo

corepack enable
yarn set version stable

adduser -gecos "" --disabled-login mastodon

sudo -u postgres psql -c "CREATE USER mastodon CREATEDB;"


## Create ruby installer in mastodon user home dir, then run.
## Note: bash -i shebang throws an error, but the interactivity is required
## "bash: cannot set terminal process group (-1): Inappropriate ioctl for device"
## "bash: no job control in this shell"
echo '#!/bin/bash -i' >> /home/mastodon/ruby.sh
echo 'git clone https://github.com/rbenv/rbenv.git ~/.rbenv' >> /home/mastodon/ruby.sh
echo 'cd ~/.rbenv && src/configure && make -C src' >> /home/mastodon/ruby.sh
echo 'echo '\''export PATH="$HOME/.rbenv/bin:$PATH"'\'' >> ~/.bashrc' >> /home/mastodon/ruby.sh
echo 'echo '\''eval "$(rbenv init -)"'\'' >> ~/.bashrc' >> /home/mastodon/ruby.sh
echo 'source ~/.bashrc' >> /home/mastodon/ruby.sh
echo 'git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build' >> /home/mastodon/ruby.sh
echo 'RUBY_CONFIGURE_OPTS=--with-jemalloc rbenv install 3.0.6' >> /home/mastodon/ruby.sh
echo 'rbenv global 3.0.6' >> /home/mastodon/ruby.sh
echo 'gem install bundler --no-document' >> /home/mastodon/ruby.sh

chmod +x /home/mastodon/ruby.sh

su -c "/home/mastodon/ruby.sh" - mastodon


## Create mastodon installer in mastodon user home dir, then run.
## Note: bash -i shebang throws an error, but the interactivity is required
## "bash: cannot set terminal process group (-1): Inappropriate ioctl for device"
## "bash: no job control in this shell"
echo '#!/bin/bash -i' >> /home/mastodon/install.sh
echo 'git clone https://github.com/tootsuite/mastodon.git ~/live && cd live' >> /home/mastodon/install.sh
echo 'git checkout $(git tag -l | grep -v '\''rc[0-9]*$'\'' | sort -V | tail -n 1)' >> /home/mastodon/install.sh
echo 'bundle config deployment '\''true'\''' >> /home/mastodon/install.sh
echo 'bundle config without '\''development test'\''' >> /home/mastodon/install.sh
echo 'bundle install -j$(getconf _NPROCESSORS_ONLN)' >> /home/mastodon/install.sh
echo 'yarn install --pure-lockfile' >> /home/mastodon/install.sh
echo 'cd /home/mastodon/live && RAILS_ENV=production bundle exec rake mastodon:setup' >> /home/mastodon/install.sh
chmod +x /home/mastodon/install.sh

su -c "/home/mastodon/install.sh" - mastodon

## Copy default nginx config file & enable it
cp /home/mastodon/live/dist/nginx.conf /etc/nginx/sites-available/mastodon
ln -s /etc/nginx/sites-available/mastodon /etc/nginx/sites-enabled/mastodon

## Uncomment and edit the example.com cert lines in the nginx config file.
## Note: the official Mastodon build instructions currently DO NOT WORK.
#### This would be preferred, but doesn't work: `certbot --nginx -d example.com` - the webroot in the config seems to prevent this from working.
#### Instead, we're running certbox in standalone mode which requires stopping of nginx, requesting certs, and restarting nginx.
#### We're manually adding a job to crontab, as well as pre/post renewal hooks for nginx stop/start, so renewal will be handled automatically.
sed -i "s,# ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;,ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;," /etc/nginx/sites-available/mastodon
sed -i "s,# ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;,ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;," /etc/nginx/sites-available/mastodon

## replace remaining instances of example.com in 80/443 blocks of config file
sed -i "s/example.com/$domain/" /etc/nginx/sites-available/mastodon

systemctl stop nginx

if $staging
then 
	certbot certonly --staging --standalone -d $domain --non-interactive --agree-tos -m $email
else 
	certbot certonly --standalone -d $domain --non-interactive --agree-tos -m $email
fi

systemctl start nginx

## Certbot renewal
## Very useful: https://eff-certbot.readthedocs.io/en/stable/using.html#automated-renewals
sudo sh -c 'printf "#!/bin/sh\nservice nginx stop\n" > /etc/letsencrypt/renewal-hooks/pre/nginx.sh'
sudo sh -c 'printf "#!/bin/sh\nservice nginx start\n" > /etc/letsencrypt/renewal-hooks/post/nginx.sh'
sudo chmod 755 /etc/letsencrypt/renewal-hooks/pre/nginx.sh
sudo chmod 755 /etc/letsencrypt/renewal-hooks/post/nginx.sh

SLEEPTIME=$(awk 'BEGIN{srand(); print int(rand()*(3600+1))}'); echo "0 0,12 * * * root sleep $SLEEPTIME && certbot renew -q" | tee -a /etc/crontab > /dev/null

## Copy, reload and enable mastodon services
cp /home/mastodon/live/dist/mastodon-*.service /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now mastodon-web mastodon-sidekiq mastodon-streaming

## Tidy up

rm /home/mastodon/install.sh
rm /home/mastodon/ruby.sh

if [ "$ur" = "22.04" ]; then
    sed -i 's/$nrconf{kernelhints} = 0;/#$nrconf{kernelhints} = -1;/' /etc/needrestart/needrestart.conf
    sed -i 's/$nrconf{restart} = '\''a'\'';/#$nrconf{restart} = '\''i'\'';/' /etc/needrestart/needrestart.conf
    sed -i 's/$nrconf{ucodehints} = 0;/#$nrconf{ucodehints} = 0;/' /etc/needrestart/needrestart.conf

    ## https://github.com/mastodon/mastodon/discussions/17221
    ## Some weird permission error that stops the CSS/JS files being served.
    chmod o+x /home/mastodon
fi

## Security hardening
## 1. Prevent root login. We've already created a new user account and copied SSH keys over.
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin no/PermitRootLogin no/' /etc/ssh/sshd_config

## 2. Prevent login using password authentication. SSH keys only.
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

systemctl restart ssh

## Last message to user
echo 'If you have created an admin user, make a note of the password ^^ above ^^'
echo 'Then, I would highly recommend a reboot...'
echo "Rememeber, you can't log back in as root. Use '$username' instead."
