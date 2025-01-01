# typed: false
# frozen_string_literal: true

class StacksAnalytic < ApplicationRecord::Domain::Stacks
  include Repositories::BelongsToRepository

  belongs_to_repository_via_domain relation_name: :template_repository, foreign_key: :template_repository_id, class_name: "Repository", feature_flag: "repos_domain_associations"

  def update_last_29_days_data_and_reset_present_day_count
    last_29_days_instance_counts = self.last_29_days_instance_counts
    current_utc_date = Time.now.utc.to_date

    # Delete stale data if we have counts from more than 29 days ago
    last_29_days_instance_counts.delete_if { |day| day["date"].to_date < current_utc_date - 29 }

    # If the last updated present day instance count is within the last 29 days, add it to the array
    if self.updated_at.to_date >= current_utc_date - 29
      last_29_days_instance_counts.push({ "date" => self.updated_at.to_date.to_s, "count" => self.present_day_instance_count })
    end

    self.transaction do
      self.update!(present_day_instance_count: 1, last_29_days_instance_counts: last_29_days_instance_counts, total_instance_count: self.total_instance_count + 1)
    end
  end

  def increment_instance_counts
    self.transaction do
      self.update!(present_day_instance_count: self.present_day_instance_count + 1, total_instance_count: self.total_instance_count + 1)
    end
  end

  def updated_today?
    self.updated_at.to_date == Time.now.utc.to_date
  end

  def update_popularity_count
    if self.updated_today?
      self.increment_instance_counts
    else
      self.update_last_29_days_data_and_reset_present_day_count
    end
  end

  def self.get_analytic(stack_instance)
    StacksAnalytic.where(template_repository_id: stack_instance.template_repository_id)&.first
  end

  def self.create_analytic_entry(stack_instance)
    StacksAnalytic.transaction do
      stacks_analytic = get_analytic(stack_instance)
      unless stacks_analytic.present?
        StacksAnalytic.create!(template_repository_id: stack_instance.template_repository_id, present_day_instance_count: 1, total_instance_count: 1, last_29_days_instance_counts: [])
      end
    end
  end

  def self.compute_stack_popularity(stacks_instance)
    stacks_analytic = get_analytic(stacks_instance)
    if stacks_analytic.present?
      stacks_analytic.update_popularity_count
    else
      create_analytic_entry(stacks_instance)
    end
  end
end
