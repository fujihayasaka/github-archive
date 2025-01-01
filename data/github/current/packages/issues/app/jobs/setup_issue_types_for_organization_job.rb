# typed: true
# frozen_string_literal: true

#TODO: the factory (https://github.com/github/github/blob/7f7484ce704710ca1f13d6de01b814f135665c80/test/factories/issue_type_factories.rb#L5)
# will have to be updated in the follow-up PR to create the issue types (maybe with an option to omit them if we need to).
class SetupIssueTypesForOrganizationJob < ApplicationJob
  use_primaries ApplicationRecord::IssuesPullRequests

  queue_as :setup_issue_types_for_organization

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(org:)
    with_write do
      IssueType.throttle do
        IssueType.create_default_issue_types_for(org)
      end
    end
  end
end
