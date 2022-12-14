# Mastodon Installer for Ubuntu 20.04/22.04 & Debian 10/11

This script follows the [JoinMastodon](https://docs.joinmastodon.org/admin/install/) instructions as closely as possible, but deviates where those instructions (currently) don't work.

- 16/11/2022 - Added Debian 10/11 support.
- 15/11/2022 - Bumped Ruby to 3.0.4 and tested installation of Mastodon v4.0.2. Working as expected.

### Assumptions about your server:
- It's a fresh installation of Ubuntu (20.04 or 22.04) or Debian (10 or 11)
- You're logged in as root using an SSH key (important because this script will disable password authentication. It will also create a new user for future logins)
- Encoding is set to UTF-8 (check with `locale`. Change with `update-locale LANG=en_US.UTF-8`, `update-locale LANG=de_DE.UTF-8` etc.) - [#1](https://github.com/techbitsio/MastodonInstaller/issues/1)

## Download

```
wget https://raw.githubusercontent.com/techbitsio/MastodonInstaller/main/main.sh && chmod +x main.sh
```
or
```
git clone https://github.com/techbitsio/MastodonInstaller.git && cd MastodonInstaller
```
## Usage

```
./main.sh
```

## Optional parameters

Script will prompt for username, email and domain if not set using below parameters. Script will prompt for new user password either way.

- `-u`. Specify username of user to be created for future logins. Script will prompt if not set. Note: this script will disable root account login and transfer ssh keys to this user. If you have already created this new user, enter the username at CLI or when prompted and it will continue. Example: `-u youruser`.
- `-e`. Specify email address to be used for fail2ban config, certbot/letsencrypt request. Example: `-e you@example.com`.
- `-d`. Domain or subdomain of instance. Used for certbot/letsencrypt request and nginx config files. Examples: `-d example.com`, `-d sub.domain.com`.
- `-s`. Staging flag. Sets certbot/letsencrypt request to staging server. Recommended if you're doing a lot of testing and don't want to exceed cert limits on main server.

### Example

`./main.sh -u newuser -e newuser@example.com -d ms.example.com -s`

## Current Limitations

There are certain interactive elements to this script, even if using command line parameters (e.g. setting new user password), but the main one is following the Mastodon install wizard.
- The domain, email parameters don't get passed through so have to be re-entered
- It would be nice to pass in a mastodon config file to make this a fully automated installation

## Issues & PRs

Issues and PRs welcome for fixes and improvements! Any questions: [@techbits@sudo.cat](https://sudo.cat/@techbits) or [@techbitsio](https://twitter.com/techbitsio).

## To Do

Basic testing of procedure against Debian 11 complete. Mostly works. Needed `export NODE_OPTIONS=--max_old_space_size=4096` before `RAILS_ENV=production bundle exec rails assets:precompile`, even with a lot of swap space.
