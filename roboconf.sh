#!/bin/bash

echo "Begin loading roboconf functions..."

function roboconf-check {
  echo -n "checking for $1... "
  hash "$1" 2>&- || {
    echo 'no'
    exit 1
  }
  echo 'yes'
}

# Since the developer may not want to merge the latest SHAs during his development,
# this function only checks out what the current parent project "thinks" are the
# current submodule SHAs.
function check_out_current_project_shas {
  roboconf-check git
  git submodule init
  git submodule sync
  git submodule update
}

# Only used for Ruby 1.x environments
function roboconf-bundler1 {
  roboconf-check ruby
  roboconf-check gem
  gem install bundler -v 1.17.3 --no-rdoc --no-ri
  # shellcheck disable=SC2086
  roboconf-bundler-install $1
}

function roboconf-bundler {
  roboconf-bundler-prepare
  # shellcheck disable=SC2086
  roboconf-bundler-install $1
}

function roboconf-bundler-dev {
  roboconf-bundler-prepare
  roboconf-bundler-without
  # shellcheck disable=SC2086
  roboconf-bundler-install $1
}

function roboconf-bundler-prepare {
  roboconf-check ruby
  roboconf-check gem
  gem install bundler --no-document
}

function roboconf-bundler-install {
  # shellcheck disable=SC2086
  bundle install $1
}

function roboconf-bundler-without {
  bundle config set --local without 'production staging'
}

function roboconf-npm {
  roboconf-check node
  roboconf-check npm
  npm install
}

function roboconf-rails-activerecord {
  bundle exec rake db:create
  bundle exec rake db:migrate
}

function roboconf-padrino-activerecord {
  bundle exec padrino rake ar:create
  bundle exec padrino rake ar:create -e test
  bundle exec padrino rake ar:migrate
  bundle exec padrino rake ar:migrate -e test
  bundle exec padrino rake seed
}

function roboconf-passenger {
  mkdir -p tmp
  touch tmp/restart.txt
}

function echo_cmd {
  echo "\$ $*"
  $*
}

function fire_up_heroku_app {
  curl "http://${app}.herokuapp.com/" &> /dev/null
}

# Loads $HEROKU_CONSTANTS or exits
function load_heroku_constants {
  if [ -z "$HEROKU_CONSTANTS" ]; then
    echo "Error: \$HEROKU_CONSTANTS is undefined"
    echo "\$HEROKU_CONSTANTS should reference a file holding key=value pairs of Heroku configuration settings"
    exit 1
  elif [[ -f $HEROKU_CONSTANTS ]]; then
    echo "Sourcing $HEROKU_CONSTANTS"
    source $HEROKU_CONSTANTS
  else
    echo "Error: Failed to find $HEROKU_CONSTANTS"
    exit 1
  fi
}

# "Private" function called by run_heroku_config_if_settings_changed.
# Sets the heroku_vars_changed variable to true/false depending on whether
# the Heroku environment variables in $HEROKU_CONSTANTS differ from what
# is currently configured for the Heroku app.
function detect_heroku_vars_changed {
  echo "Starting detect_heroku_vars_changed"

  # current app settings on Heroku
  current_configs=$(heroku config --app "$app")

  # desired new Heroku settings
  load_heroku_constants

  # test whether desired Heroku settings equal current Heroku settings
  heroku_vars_changed=false
  while read line
  do
    new_key="$( cut -d '=' -f 1 <<< $line )"
    new_value="$( cut -d '=' -f 2- <<< $line )"
    new_value=`sed -E -e "s/(^'|'$)//g" <<< $new_value` # strip leading/trailing 's
    new_value=`sed -E -e "s/(^\"|\"$)//g" <<< $new_value` # strip leading/trailing "s
    if [[ $new_key =~ 'HEROKU_CONFIG_ADD_CONSTANTS' # ignore this script-only variable; it is not a Heroku config setting
        || $new_key == \#* # ignore lines that start with '#' (comments)
        || $new_key == '' # ignore blank lines
        ]]; then
      continue
    fi
    if [[ "$current_configs" == *"$new_key"* && "$current_configs" == *"$new_value"* ]]; then
      echo "Key '$new_key' already has value '$new_value'"
    else
      heroku_vars_changed=true
      echo "Key '$new_key' will be set to value '$new_value'"
    fi
  done < $HEROKU_CONSTANTS
}

# runs 'heroku config:set' only if the Heroku configuration settings have changed
function run_heroku_config_if_settings_changed {
  echo "Starting run_heroku_config_if_settings_changed..."
  detect_heroku_vars_changed
  if ! $heroku_vars_changed; then
    echo "Skipping 'heroku config:add' because Heroku variables unchanged"
  else
    echo "Running 'heroku config:add' because Heroku variables have changed"
    heroku config:set $HEROKU_CONFIG_ADD_CONSTANTS --app "$app"
  fi
}

function show_prep_release_usage_and_exit {
  cat <<EOF
Usage: $0 heroku-app-name

Function: Release app to heroku-app-name.herokuapp.com as staging/testing environment before a release.

Example: $0 hedgeye-cedar-smarketing
Example: $0 hedgeye-smailroom
EOF
  exit 1
}

function show_release_usage_and_exit {
  cat <<EOF
Usage: $0 heroku-app-name

Function: Release app to heroku-app-name.herokuapp.com as production environment.

Example: $0 hedgeye-cedar-marketing
Example: $0 hedgeye-reader
EOF
  exit 1
}

function show_config_usage_and_exit {
  cat <<EOF
Usage: $0 heroku-app-name

Function: Update Heroku configuration.

Example: $0 hedgeye-labs
EOF
  exit 1
}

function heroku_addon {
  name="$1"
  match=$(ruby -e "puts %x(heroku addons --app "$app").match(/$name/).to_s")

  if [ '' == "$match" ]; then
    echo "Installing '$name' because it's not yet installed"
    echo_cmd heroku addons:add $name --app "$app"
  else
    echo "Not installing '$name' because it's already installed"
  fi
}

# Since database migration is performed in CMS, the db/schema.rb file
# for non-CMS applications can get out of sync.  The ./configure file
# in such projects should invoke this method to make sure that the
# db/schema.rb file is updated periodically.
#
# The 'cruise' check is to allow Jenkins to not do this, since
# non-CMS applications _do_ have their own databases and therefore
# handle db/schema.rb differently.
function dump_schema {
    if ! [[ "$TEST_ENVIRONMENT" == 'cruise' ]]; then
      bundle exec rake db:schema:dump
    fi
}

# The following two routines are needed by a script/release script:
function get_current_git_branch_name {
  git rev-parse --abbrev-ref HEAD
}

function set_current_git_branch_name {
  current_git_branch_name=$(get_current_git_branch_name)
  echo "The current branch is '$current_git_branch_name'"
}

echo "Finished loading roboconf functions"
