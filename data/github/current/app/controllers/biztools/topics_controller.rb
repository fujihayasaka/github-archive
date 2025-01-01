# typed: true
# frozen_string_literal: true

class Biztools::TopicsController < BiztoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  PER_PAGE = 30

  before_action :dotcom_required

  def index
    if params[:featured].present?
      featured = params[:featured].to_i == 1
    else
      featured = nil
    end

    topics = Topic
      .not_flagged
      .curated
      .order(updated_at: :desc)
      .paginate(page: params[:page], per_page: PER_PAGE)

    unless featured.nil?
      if featured
        topics = topics.featured
      else
        topics = topics.non_featured
      end
    end

    if query = params[:q].presence
      topics = topics.with_name_like(query)
    end

    respond_to do |format|
      format.html_fragment do
        render partial: "biztools/topics/curated_topics", formats: :html, locals: {
          featured: featured,
          query: query,
          curated_topics: topics
        }
      end
      format.html do
        render "biztools/topics/index", locals: {
          featured: featured,
          query: query,
          curated_topics: topics,
          topics_repository: importer.topics_repository
        }
      end
    end
  end

  def update
    topic_name = params[:topic]
    topic = Topic.find_or_build_by_name(topic_name)
    topic.featured = params[:featured].to_i == 1

    if !topic.save
      error = topic.errors.messages.values.join(", ")
      return render json: { error: error }, status: :unprocessable_entity
    end

    respond_to do |format|
      format.html do
        render partial: "biztools/topics/curated_topic", locals: { topic: topic }
      end
    end
  end

  def import # rubocop:todo GitHub/UseRestfulActions
    write_mode = params[:write_mode] == "1"
    dry_run = !write_mode
    importer.import(dry_run: dry_run, topic_names: params[:topics])

    unless importer.any_changes?
      flash[:notice] = "Topics in GitHub are up-to-date with those in #{TopicImporter::REPO_NWO}!"
      return redirect_to(biztools_topics_path)
    end

    if dry_run || importer.errors.any?
      render "biztools/topics/import", locals: {
        importer: importer, new_topic_changesets: importer.new_topic_changesets,
        updated_topic_changesets: importer.updated_topic_changesets,
        topics_repository: importer.topics_repository
      }
    else
      flash[:notice] = "Imported #{importer.new_count} new topic(s) and updated " +
                       "#{importer.updated_count} topic(s)."
      redirect_to biztools_topics_path
    end
  end

  private

  def importer # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_importer ||= TopicImporter.new
  end
end
