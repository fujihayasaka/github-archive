# typed: true
# frozen_string_literal: true

class Codespaces::PrebuildConfigurations::TriggerOptionsComponent < ApplicationComponent
  def initialize(form:, repo:, trigger:, delivery_days:, delivery_times:, time_zone_name:)
    @form = form
    @repo =  repo
    @trigger = trigger
    @delivery_days = delivery_days || []
    @delivery_times = delivery_times || []
    @time_zone_name = time_zone_name
  end

  def selected_trigger?(target)
    target == trigger
  end

  def selected_days
    if delivery_days.empty?
      Codespaces::PrebuildTemplateCreationSchedule::WEEKDAYS.keys
    else
      delivery_days
    end
  end

  def delivery_days_text
    return "Weekdays" if delivery_days.empty?

    if weekdays?
      "Weekdays"
    elsif weekends?
      "Weekends"
    elsif every_day?
      "Every day"
    elsif delivery_days.any?
      delivery_days.map { |d| d[0..2] }.to_sentence(last_word_connector: ", ")
    end
  end

  def weekdays?
    delivery_days == Codespaces::PrebuildTemplateCreationSchedule::WEEKDAYS.keys
  end

  def weekends?
    delivery_days == Codespaces::PrebuildTemplateCreationSchedule::WEEKENDS.keys
  end

  def every_day?
    delivery_days == Codespaces::PrebuildTemplateCreationSchedule.delivery_days.keys
  end

  # Defaults to ["9:00 AM"] for new records.
  def selected_times
    delivery_times.empty? ? ["9:00 AM"] : delivery_times
  end

  def day_options
    Codespaces::PrebuildTemplateCreationSchedule.delivery_days.keys.each_with_object({}) do |day, acc|
      acc[day] = {
        selected: selected_days.include?(day),
        css_class: Codespaces::PrebuildTemplateCreationSchedule::WEEKDAYS.key?(day) ? "js-delivery-day-weekday" : "js-delivery-day-weekend"
      }
    end
  end

  def time_options
    times = Codespaces::PrebuildTemplateCreationSchedule.delivery_times.sort_by { |_time, order| order }
    times = T.must(times[12..-1]) + T.must(times[0..12])
    options = times.each_with_object({}) do |(time_name, _order), acc|
      acc[time_name] = {
    selected: selected_times.include?(time_name)
    }
    end
  end

  def timezone_options
    selected_timezone = Codespaces::TimeZoneHelper.get_time_zone(time_zone_name: time_zone_name)
    options = Codespaces::TimeZoneHelper.timezone_options.map do |timezone|
      {
        text: "(GMT #{timezone.now.formatted_offset}) #{timezone.name}",
        value: timezone.name,
        selected: timezone == selected_timezone,
        browser_name: timezone.tzinfo.name,
      }
    end
  end

  private

  attr_reader :form, :repo, :trigger, :delivery_days, :delivery_times, :time_zone_name
end
