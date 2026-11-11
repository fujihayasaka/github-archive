# typed: true
# frozen_string_literal: true

class Stafftools::TopicsController < StafftoolsController
  include ActionView::Helpers::TextHelper

  before_action :normalize_topic, only: :show

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Configurations, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  PER_PAGE = 50

  def index
    topics = Topic.order(name: :asc).paginate(page: params[:page], per_page: PER_PAGE)
    if params[:query].present?
      query = params[:query]
      topics = topics.name_includes(query)
    end
    if params[:hide_flagged] == "1"
      topics = topics.not_flagged
    end

    render "stafftools/topics/index", locals: {
      topics: topics,
    }
  end

  def show
    topic_name = params[:topic]
    topic = Topic.find_or_build_by_name(topic_name)

    return render_404 unless topic

    render "stafftools/topics/show", layout: "application", locals: { topic: topic }
  end

  def update
    topic_name = params[:topic]
    topic = Topic.find_or_build_by_name(topic_name)

    unless topic
      flash[:error] = "Invalid topic name '#{topic_name}'"
      return redirect_to stafftools_topic_path(params[:topic])
    end

    topic.flagged = params[:flagged].to_i == 1

    if topic.save
      message = if topic.flagged?
        "Flagged topic '#{topic.name}'."
      else
        "Removed flag from topic '#{topic.name}'."
      end
      redirect_to stafftools_topic_path(topic.name), notice: message
    else
      errors = topic.errors.full_messages.join(", ")
      flash[:error] = "Could not update topic: #{errors}"
    end
  end

  def bulk_flag_by_id # rubocop:disable GitHub/UseRestfulActions
    unless params[:topic_id].present?
      flash[:warn] = "At least one topic must be selected"
      return redirect_to_index
    end

    topic_ids = params[:topic_id]
    topics = Topic.where(id: topic_ids, flagged: false)

    not_saved = []
    topics.each do |t|
      begin
        t.flagged = true
        t.save
      rescue ActiveRecord::ActiveRecordError => e
        Failbot.report(e)
        not_saved << t.name
      end
    end

    if not_saved.length == 0
      flash[:notice] = "Flagged #{pluralize(topics.length, "topic")} (skipped topics that were already flagged)"
    else
      comma_separated = not_saved.join(", ")
      flash[:warn] = "Could not flag some topics: #{comma_separated}"
    end

    redirect_to_index
  end

  def bulk_flag_matching # rubocop:disable GitHub/UseRestfulActions
    unless params[:query].present?
      flash[:warn] = "A search query must be provided to flag all matching topics"
      return redirect_to_index
    end

    topics = Topic.name_includes(params[:query]).not_flagged

    not_saved = topics.count
    topics.each do |t|
      begin
        t.flagged = true
        t.save
        not_saved -= 1
      rescue ActiveRecord::ActiveRecordError => e
        Failbot.report(e)
      end
    end

    if not_saved == 0
      flash[:notice] = "Flagged #{pluralize(topics.length, "topic")} (skipped topics that were already flagged)"
    else
      flash[:warn] = "Errors occurred while flagging. Flagged #{pluralize(topics.length - not_saved, "topic")}, did not flag #{not_saved}"
    end

    redirect_to_index(true)
  end

  private

  def normalize_topic
    normalized_name = Topic.normalize(params[:topic])
    return if normalized_name == params[:topic]

    redirect_to stafftools_topic_path(normalized_name)
  end

  def redirect_to_index(skip_hide_flagged = false)
    hide_flagged = if skip_hide_flagged
      nil
    else
      params[:hide_flagged]
    end

    redirect_to stafftools_topics_index_path(query: params[:query], page: params[:page], hide_flagged: hide_flagged)
  end
end
