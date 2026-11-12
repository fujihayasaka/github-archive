# frozen_string_literal: true

require_relative "../../app/models/github_login"

ActiveRecord::Type.register(:github_login, GitHubLogin)
