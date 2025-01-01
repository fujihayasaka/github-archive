# typed: true
# frozen_string_literal: true

module Api::Serializer::EnterpriseLicensingDependency
  extend T::Helpers

  sig do
    params(
      bla: Licensing::BundledLicenseAssignment,
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def visual_studio_subscription_assignment_hash(bla, options = {})
    {
      visual_studio_subscription_email: bla.email,
      subscription_id: bla.subscription_id,
      username: bla.user&.display_login,
      manual_match: bla.manual_match,
    }
  end

  sig do
    params(
      data: T::Hash[Symbol, T.untyped],
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def visual_studio_subscription_assignments_hash(data, options = {})
    visual_studio_subscription_assignments = data.fetch(:visual_studio_subscription_assignments, [])
    visual_studio_subscription_assignments_hashes = visual_studio_subscription_assignments.map do |visual_studio_subscription_assignment|
      visual_studio_subscription_assignment_hash(visual_studio_subscription_assignment, options)
    end
    {}.tap do |h|
      h[:total_count] = data[:total_count]
      h[:visual_studio_subscriptions] = visual_studio_subscription_assignments_hashes
    end
  end
end
