# typed: true
# frozen_string_literal: true

module Sponsors
  class PendingChangeNoticeComponent < ApplicationComponent
    extend T::Sig

    # sponsorship - a Sponsorship; if it has no upcoming change, such as a cancellation,
    #               nothing will be rendered
    # system_arguments - optional Hash of Primer system attributes to apply to the outermost `<div>`.
    #                    See https://primer.style/view-components/system-arguments
    def initialize(sponsorship:, **system_arguments)
      @sponsorship = sponsorship
      @system_arguments = system_arguments
      @class_overrides = system_arguments.delete(:classes)
    end

    private

    attr_reader :sponsorship, :system_arguments, :class_overrides
    delegate :sponsor, :sponsorable, :subscription_item, to: :sponsorship

    def render?
      sponsorship &&
        GitHub.sponsors_enabled? &&
        subscription_item &&
        logged_in? &&
        viewer_is_sponsor_admin? &&
        pending_change.present?
    end

    def viewer_is_sponsor_admin?
      current_user.potential_sponsor_ids.include?(sponsor.id)
    end

    def sponsors_pending_cycle
      sponsor.pending_cycle
    end

    sig { returns String }
    def pending_change_description
      change = T.must_because(pending_change) { "#render? requires pending change" }
      # use local var to support exhaustiveness checking
      change_type = change.type
      change_description = case change_type
      when Sponsorship::PendingChange::Type::Cancellation
        safe_join(
          [
            "Cancelling a",
            render(Primer::Beta::Text.new(tag: :strong)) { subscription_item.subscribable.to_s },
            "sponsorship of #{sponsorable}"
          ],
          " "
        )
      when Sponsorship::PendingChange::Type::Downgrade
        safe_join(
          [
            "Downgrade to",
            render(Primer::Beta::Text.new(tag: :strong).with_content(change.new_tier.to_s)),
          ],
          " "
        )
      when Sponsorship::PendingChange::Type::Activation
        safe_join(
          [
            "Activating a",
            render(Primer::Beta::Text.new(tag: :strong).with_content(change.new_tier.to_s)),
            "sponsorship of #{sponsorable}",
          ],
          " "
        )
      # We don't expect to handle upgrades or no-op pending changes, but they're implemented to allow for
      # an exhaustiveness check.
      when Sponsorship::PendingChange::Type::Upgrade
        "Pending upgrade"
      when Sponsorship::PendingChange::Type::NOP
        "Pending change"
      else
        T.absurd(change_type)
      end

      effective_date = sponsors_pending_cycle.active_on.strftime("%b %d, %Y")
      effective_date_description = safe_join(
        [
          "effective on",
          render(Primer::Beta::Text.new(tag: :strong).with_content(effective_date)),
        ],
        " "
      )

      safe_join([
        change_description,
        ", ",
        effective_date_description,
        "."
      ])
    end

    def undo_pending_change_url
      sponsorable_pending_sponsorship_changes_path(sponsorable, sponsor: sponsor)
    end

    sig { returns T.nilable(Sponsorship::PendingChange) }
    memoize def pending_change
      sponsorship.pending_change
    end
  end
end
