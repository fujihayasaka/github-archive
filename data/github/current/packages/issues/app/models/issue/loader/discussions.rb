# typed: true
# frozen_string_literal: true

class Issue::Loader::Discussions < Issue::Loader::Base
  def initialize(context, conversion_events: [])
    @context = context
    @conversion_events = conversion_events
  end

  def self.load_for(context, conversion_events: [])
    super new(context, conversion_events: conversion_events)
  end

  def load
    if @conversion_events.empty?
      @context.preload_attr(:converted_discussions_by_event_id, {})
      return {}
    end

    subject_ids = @conversion_events.map(&:subject_id)
    discussions = Discussion.
      strict_loading.
      where(id: subject_ids).
      index_by(&:id)

    converted_discussions_by_event_id = @conversion_events.each_with_object({}) do |event, result|
      result[event.id] = discussions[event.subject_id]
    end

    @context.preload_attr(:converted_discussions_by_event_id, converted_discussions_by_event_id)
  end
end
