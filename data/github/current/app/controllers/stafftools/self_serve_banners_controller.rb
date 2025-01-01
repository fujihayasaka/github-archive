# typed: true
# frozen_string_literal: true

class Stafftools::SelfServeBannersController < StafftoolsController
  before_action :dotcom_required

  depends_on_clusters \
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Stafftools::SelfServeBannersController#create",
    "Stafftools::SelfServeBannersController#update"
  ].freeze, T::Array[String])

  BATCH_SIZE = 1000

  def index
    self_serve_banners = CopilotPLG::SelfServeBanner.all

    render "stafftools/self_serve_banners/show", locals: { banners: self_serve_banners }
  end

  def edit
    banner = CopilotPLG::SelfServeBanner.find(params[:id])

    render "stafftools/self_serve_banners/edit", locals: { banner: banner }
  end

  def update
    banner = CopilotPLG::SelfServeBanner.find(params[:id])

    banner.update(
      title: params[:title],
      body: params[:body],
      cta_url: params[:cta_url],
      cta_text: params[:cta_text],
      visibility: params[:visibility]
    )

    if params[:csv_file].present?
      result, failure_message = process_csv(params[:csv_file], params[:slug])
      if result == false
        flash[:error] = "Error processing CSV file: #{failure_message}"
        render "stafftools/self_serve_banners/edit", locals: { banner: banner }
        return
      end
    end

    if banner.persisted?
      # Handle Success
      flash[:notice] = if flash[:notice].blank?
        "Banner updated successfully."
      else
        "#{flash[:notice]} Banner updated successfully."
      end
      redirect_to stafftools_self_serve_banners_path
    else
      # Handle error
      flash[:error] = "Error updating banner: #{banner.errors.full_messages.to_sentence}"
      render "stafftools/self_serve_banners/edit", locals: { banner: banner }
    end
  end

  def new
    render "stafftools/self_serve_banners/new"
  end

  def create
    banner = CopilotPLG::SelfServeBanner.create!(
      slug: params[:slug],
      title: params[:title],
      body: params[:body],
      cta_url: params[:cta_url],
      cta_text: params[:cta_text],
      visibility: params[:visibility]
    )

    if params[:csv_file].present?
      result, failure_message = process_csv(params[:csv_file], params[:slug])
      if result == false
        flash[:error] = "Error processing CSV file: #{failure_message}"
        render "stafftools/self_serve_banners/new", locals: { banner: banner }
        return
      end
    end

    if banner.persisted?
      # Handle Success
      flash[:notice] = if flash[:notice].blank?
        "Banner created successfully."
      else
        "#{flash[:notice]} Banner created successfully."
      end
      redirect_to stafftools_self_serve_banners_path
    else
      # Handle error
      flash[:error] = "Error creating banner: #{banner.errors.full_messages.to_sentence}"
      render "stafftools/self_serve_banners/new", locals: { banner: banner }
    end
  end

  private

  sig { params(csv_file: T.nilable(ActionDispatch::Http::UploadedFile), slug: String).returns([T::Boolean, String]) }
  def process_csv(csv_file, slug)
    processed_file = false
    failure_message = ""

    return [false, "No CSV file provided"] if csv_file.nil?

    user_ids = Set.new
    begin
      File.open(T.must(csv_file.path), "r") do |file|
        first_line = file.readline.strip
        has_header = first_line == "github_user_ids"

        file.each_line do |line|
          stripped_line = line.strip.chomp(",")
          next if stripped_line.empty?
          user_ids << stripped_line
        end
        user_ids << first_line unless has_header || first_line.empty?
      end

      failure_message = "CSV file is empty" if user_ids.empty?

      update_kv_store_with_user_ids(user_ids, slug)
      processed_file = true
    rescue EOFError, Errno::ENOENT => e
      failure_message = "Error reading CSV file: #{e.message}"
    end

    [processed_file, failure_message]
  end

  sig { params(user_ids: T::Set[String], slug: String).void }
  def update_kv_store_with_user_ids(user_ids, slug)
    CopilotPLG::KV.mdel_prefix("user.#{slug}-visible.")
    enqueue_user_id_batches(user_ids, slug)
    flash[:notice] = "#{user_ids.length} users processed successfully."
  end

  sig { params(user_ids: T::Set[String], slug: String).void }
  def enqueue_user_id_batches(user_ids, slug)
    user_ids.each_slice(BATCH_SIZE) do |batch|
      CopilotPLG::UploadBannerUserIdsJob.perform_later(user_ids: batch.to_a, slug: slug)
    end
  end
end
