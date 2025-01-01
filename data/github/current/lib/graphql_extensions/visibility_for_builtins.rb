# typed: true
# frozen_string_literal: true

module GraphQLExtensions
  module VisibilityForBuiltIns
    ALL_ENVIRONMENTS = [:dotcom, :enterprise]
    DEFAULT_VISIBILITIES = [:internal, :public]
    DEFAULT_ENVIRONMENT_VISIBILITIES = { dotcom: DEFAULT_VISIBILITIES, enterprise: DEFAULT_VISIBILITIES }

    def visibility_for(env)
      DEFAULT_VISIBILITIES
    end

    def visibility
      DEFAULT_VISIBILITIES
    end

    def environment_visibilities
      DEFAULT_ENVIRONMENT_VISIBILITIES
    end
  end
end
