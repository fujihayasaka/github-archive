# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::AdvancedSecurity::TrialsController < Stafftools::Businesses::BusinessBaseController
  sig { void }
  def update
    operation_id = params[:operation_id]
    case operation_id
    when "expire_trial"
      result = this_business.end_advanced_security_trial(actor: current_user, is_stafftools_action: true)
      if result.ok?
        flash[:notice] = "Expired Advanced Security Trial and disabled GHAS features."
      else
        flash[:error] = "Failed to expire Advanced Security Trial: #{result.error.message}"
      end
      redirect_to stafftools_enterprise_path(this_business)
    when "extend_trial"
      result = this_business.extend_advanced_security_trial(actor: current_user, days: 7, is_stafftools_action: true)
      if result.ok?
        end_trial_date = result.value!.ends_on.strftime("%b %d, %Y")
        flash[:notice] = "Extended the Advanced Security trial. Trial will end on #{end_trial_date}."
      else
        flash[:error] = "Failed to extend Advanced Security Trial: #{result.error.message}"
      end
      redirect_to stafftools_enterprise_path(this_business)
    else
      render_404
    end
  end
end
