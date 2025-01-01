# typed: true
# frozen_string_literal: true

module RepositoryAdvisories
  class CreditView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    STATUS_ORDER = [:accepted, :pending, :declined, :not_notified, :not_saved]

    def self.for_advisory_credits(advisory_credits, current_user:, viewer_can_manage: false)
      credit_views = []

      advisory_credits.each do |advisory_credit|
        credit_view = new(
          advisory_credit: advisory_credit,
          current_user: current_user,
          viewer_can_manage: viewer_can_manage
        )

        credit_views << credit_view if credit_view.visible?
      end

      credit_views.sort!
      credit_views
    end

    attr_reader :advisory_credit
    attr_reader :viewer_can_manage
    # Signals if the advisory credit is newly added and unsaved in the database
    attr_reader :is_unsaved_advisory_credit

    delegate :id,
      :notified_at,
      :accepted_at,
      :declined_at,
      :recipient,
      :marked_for_destruction?,
      :repository_advisory,
      :credit_type,
      to: :advisory_credit

    def name
      recipient.profile_name.presence
    end

    def display_login
      recipient.display_login
    end

    def recipient_id
      recipient.id
    end

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def status_message
      @status_message ||=
        case status
        when :accepted
          "Accepted #{helpers.time_ago_in_words(accepted_at)} ago"
        when :declined
          "Declined #{helpers.time_ago_in_words(declined_at)} ago"
        when :pending
          "Pending for #{helpers.time_ago_in_words(notified_at)}"
        when :not_notified
          "Credited user not yet notified"
        when :not_saved
          "Credit not yet saved"
        end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def status_icon_name
      case status
      when :accepted then "check"
      when :declined then "x"
      when :pending then "dot-fill"
      when :not_notified, :not_saved then "dot"
      end
    end

    def status_icon_color
      case status
      when :accepted then :success
      when :declined then :danger
      when :pending, :not_notified then :attention
      when :not_saved then :muted
      end
    end

    def visible?
      recipient.present? && advisory_credit.readable_by?(current_user)
    end

    # Show the status of the credit  if the viewer can manage the advisory, i.e. if they are a collaborator.
    def show_status?
      viewer_can_manage
    end

    def <=>(other)
      sorter <=> other.sorter
    end

    def sorter
      [STATUS_ORDER.index(status).to_i, id.to_i]
    end

    private

    def status
      @status ||=
        if accepted_at
          :accepted
        elsif declined_at
          :declined
        elsif notified_at
          :pending
        elsif id
          :not_notified
        else
          :not_saved
        end
    end

    def helpers
      return @helpers if @helpers

      helpers = Module.new
      helpers.extend(ActionView::Helpers::DateHelper)

      @helpers = helpers
    end
  end
end
