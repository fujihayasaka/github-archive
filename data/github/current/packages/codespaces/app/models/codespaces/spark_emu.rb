# typed: true
# frozen_string_literal: true

# Spark requires some custom logic to to allow creation of codespaces for the
# github/spark-template repo which not all enterprise settings all by default.
module Codespaces
  module SparkEmu
    sig do
      params(
        user: User,
        repository: T.nilable(Repository),
      ).returns(T::Boolean)
    end
    def self.is_spark_emu?(user, repository)
      # The EMU check is lighter than our spark enabled check in term of DB calls
      # so do that first.
      return false unless user.is_enterprise_managed? && user.enterprise_managed_business.present?

      # We're a Spark repo if either we're the spark-template itself (unpublished)
      # or if we're a repo that was published from spark-template
      is_spark_repo = repository&.name_with_display_owner == "github/spark-template" ||
        repository&.template_repository&.name_with_display_owner == "github/spark-template"

      return false unless is_spark_repo

      user.spark_enabled?
    end

    sig do
      params(
        user: User,
      ).returns(T.nilable(Organization))
    end
    def self.organization_for_emu(user)
      return nil unless user.is_enterprise_managed? && user.enterprise_managed_business.present?

      # This path can be called multiple times while seat assignments are being
      # created/updated (for example, in test setup and job flows). Using a
      # request-cached wrapper can return stale seat data from earlier calls.
      copilot_user = Copilot::Public::User.new(user)
      desired_seat = copilot_user.copilot_seats.find do |seat|
        owner = seat.seat_assignment.owner
        next false unless owner.is_a?(::Organization)

        owner.business == user.enterprise_managed_business
      end
      desired_seat&.seat_assignment&.owner
    end
  end
end
