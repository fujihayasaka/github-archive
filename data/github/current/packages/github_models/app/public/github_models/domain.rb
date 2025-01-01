# typed: strict
# frozen_string_literal: true

module GitHubModels
  class Domain < GH::Domain::Base
    accessor GitHubModels::Domain::Blocks
    accessor GitHubModels::Domain::Models
    accessor GitHubModels::Domain::Presets
    accessor GitHubModels::Domain::Usage
  end
end
