# typed: true
# frozen_string_literal: true

# A checker that checks for star records for a given user and entity list
#
# Initialization arguments
#
#   user_id - The id of the user record that we will be checking.
#   entity_types_and_ids - an Array of String objects in this format:
#     "#{entity_class}:#{entity_id}"
#
#     Example
#       ["Gist:24", "Topic:45", "Repository:41"]
#
# Usage Example
#
#   checker = HasStarredChecker.new(12, ["Gist:24", "Topic:45", "Repository:41"])
#   checker.run
#   # => { "Gist:24" => false, "Topic:45" => true, "Repository:41" => true }

class HasStarredChecker
  def initialize(user_id, entity_types_and_ids)
    @user_id = user_id
    @entity_types_and_ids = entity_types_and_ids
  end

  def run
    return Hash.new if entity_types_and_ids.blank?

    has_starred_checks = entity_types_and_ids.map { |type_and_id| [type_and_id, false] }.to_h

    query_results.each_with_object(has_starred_checks) do |result, starred|
      key = if result.is_a?(GistStar)
        "Gist:#{result.gist_id}"
      else
        "#{result.starrable_type}:#{result.starrable_id}"
      end

      starred[key] = true
    end
  end

  private

  attr_reader :user_id, :entity_types_and_ids

  def query_results
    ActiveRecord::Base.connected_to(role: :reading) do
      [].tap do |results|
        if gist_stars_queries.present?
          results.concat(GistStar.where(gist_stars_queries.join(" OR ")))
        end

        if repo_and_topic_stars_queries.present?
          results.concat(Star.where(repo_and_topic_stars_queries.join(" OR ")))
        end
      end
    end
  end

  def gist_entities_and_ids
    @gist_entities_and_ids ||= entity_type_and_id_pairs.select do |type, _|
      type == "Gist"
    end
  end

  def repo_and_topic_entities_and_ids
    entity_type_and_id_pairs - gist_entities_and_ids
  end

  def entity_type_and_id_pairs
    @entity_type_and_id_pairs ||= entity_types_and_ids.map do |entity_type_and_id|
      type, id = entity_type_and_id.split(":")
      [type, id]
    end
  end

  def gist_stars_queries
    @gist_stars_queries ||= gist_entities_and_ids.map do |_, id|
      "(gist_id = #{sanitize(id)} AND user_id = #{user_id})"
    end
  end

  def repo_and_topic_stars_queries
    @repo_and_topic_stars_queries ||= repo_and_topic_entities_and_ids.map do |type, id|
      "(starrable_type = #{sanitize(type)} AND "\
      "starrable_id = #{sanitize(id)} AND user_id = #{user_id})"
    end
  end

  def sanitize(string)
    Star.connection.quote(string)
  end
end
