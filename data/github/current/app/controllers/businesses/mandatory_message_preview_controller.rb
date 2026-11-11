# typed: true
# frozen_string_literal: true

class Businesses::MandatoryMessagePreviewController < Businesses::BusinessController
  before_action :enterprise_required
  before_action :login_required
  before_action :business_owner_required

  def create
    render "mandatory_messages/show", locals: {
      preview: params[:custom_message_preview_value]
    }
  end
end
