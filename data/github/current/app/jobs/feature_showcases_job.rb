# typed: true
# frozen_string_literal: true

class FeatureShowcasesJob < ApplicationJob
  queue_as :feature_showcases

  exempt_from_tenant_context_requirement

  def perform
    today = Time.now
    return unless today.monday?

    with_write do
      # clear current featured showcases
      Showcase::Collection.where(featured: false).update_all(featured: true)

      # feature all 9 in the group
      Showcase::Collection.where(id: featured_ids).update_all(featured: true)
    end
  end

  def featured_ids
    # grab all the new showcases in the past 2 weeks
    featured_ids = with_write do
      Showcase::Collection.published.where("created_at > ?", 2.weeks.ago).limit(9).map(&:id)
    end

    # count how many more we need to get to 9
    remainder = 9 - featured_ids.count

    # grab the remainder by random showcases
    unless remainder == 0
      conditions = remainder == 9 ? "" : ["id not in (?)", featured_ids]

      with_write do
        featured_ids.concat(Showcase::Collection.published.where(conditions).order(Arel.sql("RAND()")).limit(remainder).map(&:id))
      end
    end
  end
end
