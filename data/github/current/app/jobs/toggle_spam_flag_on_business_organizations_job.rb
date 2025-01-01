# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Toggle the spam flag on all a Business' member Organizations.
class ToggleSpamFlagOnBusinessOrganizationsJob < ApplicationJob
  queue_as :spam
  retry_on_dirty_exit

  # Perform the job.
  #
  # business - Business whose member Organizations should be marked spammy or not spammy.
  # spammy - Boolean indicating whether to mark spammy or not spammy.
  # params - Hash of params passed to the underlying call to change the spam flag.
  def perform(business, spammy, params = {})
    return unless GitHub.spamminess_check_enabled?
    return unless business

    # Add context to the reason for member orgs
    if params[:reason].present?
      spammy_part = spammy ? "spammy" : "not spammy"
      params[:reason] = "The owning #{business.slug} enterprise was marked #{spammy_part}: #{params[:reason]}"
    end

    business.organizations.each do |org|
      with_write do
        if spammy
          org.mark_as_spammy(params)
        else
          org.mark_not_spammy(params)
        end
      end
    end
  end
end
