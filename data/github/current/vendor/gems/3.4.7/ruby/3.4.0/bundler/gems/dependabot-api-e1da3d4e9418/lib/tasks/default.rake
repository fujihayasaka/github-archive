# frozen_string_literal: true

# Clear the default rake task so we don't failover to running rspec if no
# command is given.
Rake::Task[:default].clear
