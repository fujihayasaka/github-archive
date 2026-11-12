# typed: true
# frozen_string_literal: true

class AdvisoriesController < ApplicationController
  include AdvisoryDB::CvssScore

  before_action :dotcom_required, only: [:get_package_url]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    only: [:cwe_autocomplete, :get_package_url]

  def calculate_cvss_score # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        cvss = params[:cvss_v4].present? ? parse_cvss(params[:cvss_v4]) : parse_cvss(params[:cvss_v3])

        render json: {
          score: score_from_parsed_cvss(cvss),
          severity: severity_from_parsed_cvss(cvss)
        }
      end
    end
  end

  def cwe_autocomplete # rubocop:todo GitHub/UseRestfulActions
    cwes = CWE.limit(10).order(id: :asc)
    cwes = cwes.with_content_like(params[:q]) if params[:q].present?

    respond_to do |format|
      format.html_fragment do
        render partial: "repos/advisories/autocomplete_cwes", locals: { cwes: cwes, field_name_prefix: params[:type] }, formats: :html
      end
    end
  end

  def get_package_url # rubocop:todo GitHub/UseRestfulActions
    ecosystem, package_name = params[:ecosystem], params[:package_name]&.strip

    # Reject package names that look like absolute or protocol-relative URIs to prevent SSRF via URI.join
    if package_name.present? && package_name.match?(%r{\A([a-z][a-z0-9+\-.]*:)?//}i)
      return respond_to do |format|
        format.json { render json: { error: "invalid_package_name" }, status: :bad_request }
      end
    end

    advisory_package_url = AdvisoryPackageUrl.new(ecosystem, package_name)

    respond_to do |format|
      format.json do
        if !advisory_package_url.supported_ecosystem?
          render json: { error: "unsupported" }, status: :not_found
        elsif !(package_url = advisory_package_url.get_url)
          render json: { error: "not_found" }, status: :not_found
        else
          render json: { package_url: package_url }, status: :ok
        end
      end
    end
  end

  # CAP bypass is fine here as advisories are public.
  private def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
