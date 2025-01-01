# typed: true
# frozen_string_literal: true

require "chatops-controller"
require "terminal-table"

module Chatops
  class SearchController < ApplicationController
    include ::Chatops::Controller

    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
    skip_before_action :verify_authenticity_token

    depends_on_clusters ApplicationRecord::Mysql1, only: [:list]

    chatops_help "Commands for working with production search indices"

    chatops_namespace :search
    chatops_error_response "More information is available [in Sentry](https://sentry.io/organizations/github/issues/)"

    chatop :indices,
      /indices(?:\s+(?<cluster>\S+))?/,
      "indices [cluster] - List all search indices" do

        rpc_params = jsonrpc_params.permit(:cluster, :message_id)
        cluster = rpc_params[:cluster]
        enum = Elastomer.router.each_index_config
        enum = enum.select { |ic| cluster == ic.cluster } if cluster.present?

        response = if enum.any?
          table = Terminal::Table.new(headings: %w[Name Cluster Primary Readble Writable])
          enum.each { |ic| table << [ic.name, ic.cluster, (ic.primary? ? "X" : ""), (ic.readable? ? "X" : ""), (ic.writable? ? "X" : "")] }
          table.align_column(2, :center)
          table.align_column(3, :center)
          table.align_column(4, :center)
          "```\n#{table}\n```"
        else
          "No indices were found for search cluster #{cluster.inspect}"
        end

        chatop_send response
      end

    chatop :repair,
      /repair\s+(?<command>start|stop|status|reset)\s+(?<index>\S+)/,
      "repair <start|stop|status|reset> <index> [--count <num>] [--days_ago <num>]- Execute the repair command for the given index" do

        rpc_params = jsonrpc_params.permit(:command, :index, :count, :message_id, :"visited-after", :days_ago)
        opts = {
          command: rpc_params[:command],
          index_name: rpc_params[:index],
          args: []
        }
        if opts[:command] == "start"
          count = rpc_params[:count] || 1
          days_ago = rpc_params[:days_ago] || nil
          opts[:args].push(count)
          unless days_ago.nil?
            end_date = Time.now.utc
            start_date = (end_date - days_ago.to_i.days).beginning_of_day
            opts[:args].push(start_date, end_date)
          end
        end

        klass = Search::Chatops::RepairIndex
        if opts[:index_name].start_with?("memex-project-items")
          if opts[:command] == "start"
            count = Integer(rpc_params[:count] || 1)
            opts[:args] = [count, rpc_params[:"visited-after"]]
          end

          klass = Search::Chatops::MemexProjectItemsRepairIndex
        end

        result = klass.run(**opts)
        chatop_send result
      end

    chatop :templates,
      /templates(?:\s+(?<cluster>\S+))?/,
      "templates [cluster] - List all search templates" do

        rpc_params = jsonrpc_params.permit(:cluster, :message_id)
        cluster = rpc_params[:cluster]
        templates = if cluster.present?
          SearchIndexTemplateConfiguration.where(cluster: cluster)
        else
          SearchIndexTemplateConfiguration.all
        end

        response = if templates.any?
          table = Terminal::Table.new(headings: %w[Name Cluster Primary Writable])
          templates.each { |tc| table << [tc.fullname, tc.cluster, (tc.primary? ? "X" : ""), (tc.writable? ? "X" : "")] }
          table.align_column(2, :center)
          table.align_column(3, :center)
          "```\n#{table}\n```"
        else
          "No templates were found for search cluster #{cluster.inspect}"
        end

        chatop_send response
      end

    chatop :template,
      /template\s+(?<command>create|promote|delete)\s+(?<template>\S+)(?:\s+(?<cluster>\S+))?/,
      "template <create|promote|delete> <template> [cluster] - Manage search index templates" do

        rpc_params = jsonrpc_params.permit(:command, :template, :cluster, :writable, :message_id)
        opts = {
          cluster: rpc_params[:cluster].presence,
          command: rpc_params[:command],
          template_name: rpc_params[:template],
          writable: rpc_params[:writable],
        }
        opts[:cluster] = "default" if opts[:cluster].nil?
        opts[:writable] = true if opts[:writable].nil?

        result = Search::Chatops::TemplateManagement.run(**opts)
        chatop_send result
      end
  end
end
