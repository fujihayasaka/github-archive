# typed: true
# frozen_string_literal: true

class PlanningTrackingSurveyResult
  DEFAULT_SETTINGS = {
    roadmap_feature_requested: true,
    tasklist_feature_requested: true
  }

  def self.survey_cache_key(member_id, actor_id)
    "projects-onboarding-#{member_id}-#{actor_id}"
  end

  def self.store_survey_results(membership, survey_answers)
    roadmap_answer = survey_answers.find { |answer| answer.question.short_text == "roadmap" }
    tasklist_answer = survey_answers.find { |answer| answer.question.short_text == "tasklists" }

    roadmap_feature_requested = !roadmap_answer.nil?
    tasklist_feature_requested = !tasklist_answer.nil?

    if !roadmap_feature_requested && !tasklist_feature_requested
      # if user submitted form without choosing any options, add them to both wait lists
      roadmap_feature_requested = true
      tasklist_feature_requested = true
    end

    # store form details in KV so we can retrieve them later
    key = survey_cache_key(membership.member_id, membership.actor_id)
    value = {
      roadmap_feature_requested: roadmap_feature_requested,
      tasklist_feature_requested: tasklist_feature_requested
    }

    GitHub.kv.set(key, value.to_json) # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def self.get_survey_results(membership)
    key = survey_cache_key(membership.member_id, membership.actor_id)
    settings_json = GitHub.kv.get(key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv

    return DEFAULT_SETTINGS if settings_json.nil?

    begin
      settings_hash = JSON.parse(settings_json, { symbolize_names: true })
      roadmap_feature_requested = settings_hash[:roadmap_feature_requested]
      tasklist_feature_requested = settings_hash[:tasklist_feature_requested]

      {
        roadmap_feature_requested: roadmap_feature_requested,
        tasklist_feature_requested: tasklist_feature_requested
      }
    rescue JSON::ParserError
      DEFAULT_SETTINGS
    end
  end

  def self.clear_survey_result(membership)
    key = survey_cache_key(membership.member_id, membership.actor_id)
    GitHub.kv.del(key) # rubocop:todo GitHub/DoNotUseGlobalKv
  end
end
