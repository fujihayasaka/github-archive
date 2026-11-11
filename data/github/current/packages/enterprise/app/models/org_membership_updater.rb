# typed: true
# frozen_string_literal: true

# The runner for updating org memberships in bulk on GitHub Enterprise.
class OrgMembershipUpdater

  class Error < StandardError
  end

  # Create a new org membership bulk updater.
  #
  # membership_visibility: - A String representing the visibility that all org
  #                          memberships should be updated to. Must be either
  #                          "public" or "private".
  #
  def initialize(membership_visibility:)
    raise Error, "Updating organization memberships in bulk is only supported on GitHub Enterprise" unless GitHub.enterprise?
    raise ArgumentError, %Q[membership_visibility must be "public" or "private"] unless %w(public private).include?(membership_visibility)
    @membership_visibility = membership_visibility
  end

  # Bulk updates org memberships across the installation.
  def run
    scope = Organization.all
    iterator = GitHub::QueryBatching::ScopeIterator.new(scope, batch_size: 100)

    iterator.each do |org|
      case @membership_visibility
      when "public"
        publicize_all_org_members(org)
      when "private"
        conceal_all_org_members(org)
      end
    end
  end

  private

  def publicize_all_org_members(org)
    org.people.each do |member|
      org.publicize_member(member) unless org.public_member?(member)
    end
  end

  def conceal_all_org_members(org)
    org.public_members.to_a.each do |member|
      org.conceal_member(member)
    end
  end
end
