# typed: true
# frozen_string_literal: true

class Businesses::LongDescriptionController < Businesses::BusinessController
  before_action :business_owner_required

  def update
    if this_business.update(long_description_params)
      redirect_to enterprise_path(this_business), notice: "Enterprise README updated."
    else
      redirect_to enterprise_path(this_business), flash: { error: this_business.errors.full_messages.join(", ") }
    end
  end

  private

  memoize def long_description_params
    params.require(:business).permit(:long_description)
  end
end
