# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveEnterpriseAccountsKeyValues < MoveKeyValuesBase
      class EnterpriseAccountsKeyValues < ApplicationRecord::Domain::Users
        self.table_name = :enterprise_accounts_key_values
      end

      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        EnterpriseAccountsKeyValues
      end

      iterate_key_values [
        "user.set\\_notice.org\\_attachment\\_failure.%.%",
        "organization\\_upgrade\\_purchase\\_initiated/%",
        "enterprise:maintenance",
        "enterprise:hide-warning:certificate-expiring:%",
        "enterprise:announcement",
        "user.set\\_business\\_notice.org\\_upgrade\\_onboarding.%.%",
        "deletion\\_date\\_for\\_expired\\_trial\\_business.%",
        "expired\\_trial\\_business\\_email\\_sent.%",
        "business\\_member\\_invitations/reinvited\\_count/business:%/role:%/invitee\\_id:%/email:%",
        "business\\_organization\\_invitations/last\\_reminded/%",
        "enterprise:mandatory\\_message",
        "user.mandatory\\_message\\_viewed.%",
        "org-enterprise-upgrade-in-progress.%",
        "user.large\\_scale\\_contributor.%",
        "verify\\_org\\_domain\\_attempt.%.%",
        "business-membership-removed.%:%",
      ]
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(cleanup))

  GitHub::Transitions::MoveEnterpriseAccountsKeyValues.new(args).run
end
