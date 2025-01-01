# typed: true
# frozen_string_literal: true

require "chatops-controller"

class Chatops::TableownersController < ApplicationController
  include ::Chatops::Controller

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  chatops_namespace :tableowners
  chatops_help "Get the owner for a monolith database table with `.tableowners for table`."
  chatops_error_response "Try re-running the command or ask for help in [#eng-maintainership](https://github-grid.enterprise.slack.com/archives/CGYKZBE07)."

  depends_on_clusters ApplicationRecord::Mysql1,
  only: [:list]

  private def verify_authenticity_token?
    false # robots do this
  end

  memoize def tableowners # rubocop:disable GitHub/UseRestfulActions
    YAML.safe_load(File.read("db/tableowners.yaml"), permitted_classes: [Symbol, String])
  end

  chatop :for,
  /for (?<table>.+)/,
  "for <table> - Find the service owner for a monolith table." do
    table = jsonrpc_params.require(:table)

    if tableowners.key?(table)
      service = tableowners[table]
      chatop_send("Table `#{table}` belongs to the [#{service} service](https://catalog.githubapp.com/services/#{service}).")
    else
      # TODO: Differentiate between "non-existent" and "unowned" somehow.
      chatop_send("Table `#{table}` either does not exist or is unowned.")
    end
  end
end
