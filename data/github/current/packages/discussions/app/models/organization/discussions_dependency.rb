# typed: true
# frozen_string_literal: true

class Organization
  module DiscussionsDependency
    include Configurable::DiscussionsEnablement
    extend ActiveSupport::Concern

    included do
      T.bind(self, T.class_of(Organization))

      has_one :discussion_repository,
        class_name: "OrganizationDiscussionConfig",
        required: false,
        dependent: :destroy
    end
  end
end
