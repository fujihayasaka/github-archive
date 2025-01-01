# frozen_string_literal: true

# Reloads the github config.yml file. This happens automatically when 'github' is
# required but needs to be run again after configs under config/environments/* are
# run to re-establish custom values.
#
# The config.yml file is the primary means of configuring GitHub Enterprise.
GitHub.import_yaml_config("#{Rails.root}/config.yml")
