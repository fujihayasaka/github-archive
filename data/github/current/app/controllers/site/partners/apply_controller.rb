# typed: true
# frozen_string_literal: true

class Site::Partners::ApplyController < Site::BaseController
  layout "site"
  javascript_bundle "technology-partners"

  # Please do not copy or replicate this code. We're disabling linting rule to allow dynamic template rendering for the TPE site migration. We have consulted the marketing-engineering team and we have been instructed to do so. You can read more about the project at this issue https://github.com/github/technology-partnerships-and-engineering/issues/3189
  def index
    render "site/partners/apply/index" # rubocop:disable GitHub/RailsViewRenderPathsExist, GitHub/RailsControllerRenderLiteral
  end

  def create
    eloqua_fields = %i[
      elqFormName
      elqSiteId
      elqCampaignId
      partnershipType
      challenge

      firstName
      emailAddress
      company
      formCountry
      field16
      field17
      field18
      field19
      field20
      stateProv
      stateProv2

      formCountry2
      field24
      field25
      field26

      partnerinvolvement
      lastName
      title
      business_website
      phone1
      msftpartner

      github_org
      github_handle
      technology_partner_categories
      additionalinfofrompartner
      partner_reason

      country
      subdivision
      incorporation_location
      challenge

      elqCustomerGUID
      elqCookieWrite
    ]
    cleaned = params.except(:authenticity_token, :commit)
    form_data = cleaned
    .permit(
      *eloqua_fields,
      technology_partner_categories: []
    )
    .to_h
    .delete_if { |_, v| v.blank? }

    form_data[:country] = form_data[:formCountry]
    # Ideally, this should be generated each time with a deterministic key
    form_data[:challenge] = "KHv06mNH0osgOOFwfSla"
    form_data[:subdivision] = form_data[:field16] || form_data[:field17] || form_data[:field18]
    form_data[:incorporation_location] = form_data[:formCountry]

    body = URI.encode_www_form(form_data)

    client = GitHub::FaradayClient.external(
    "partners_apply",
    "https://s88570519.t.eloqua.com",
    request: {
      timeout:      10,
      open_timeout:  5
    }
  )

    response = client.post("/e/f2") do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded" # rubocop:disable GitHub/RailsControllerRenderPathsExist
      req.body = body
    end


    if response.success?
      redirect_to "/partners/thankyou"
    else
      Rails.logger.error "Eloqua error #{response.status}: #{response.body}"
      flash.now[:alert] = "Submission failed; please try again."
      head :bad_request
    end
  end
end
