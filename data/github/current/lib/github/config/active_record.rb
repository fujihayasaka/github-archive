# typed: true
# frozen_string_literal: true

# Loads and configures minimal dependencies to enable ActiveRecord. The
# GitHub.mysql2 connection is configured along with ActiveRecord::Base.connection.
require "github/config/mysql"
GitHub.load_activerecord
