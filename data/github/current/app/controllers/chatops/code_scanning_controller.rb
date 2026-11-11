# typed: true
# frozen_string_literal: true

require "chatops-controller"

class Chatops::CodeScanningController < ApplicationController
  include ::Chatops::Controller

  # CAP not required on chatops controllers
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  chatops_namespace :code_scanning
  chatops_help "Commands for getting Code scanning chatops katas"
  chatops_error_response "Try re-running the command or ask for help in [#code-scanning](https://github.slack.com/archives/CP9GMKJCE)."

  depends_on_clusters ApplicationRecord::Mysql1,
  only: [:list]

  private def verify_authenticity_token?
    false # robots do this
  end

  def katas # rubocop:todo GitHub/UseRestfulActions
    YAML.safe_load(File.read("app/controllers/chatops/code_scanning/katas.yml"))
  end

  chatop :kata,
          /kata/,
          "kata - Get a random code scanning ops kata (short excercise)" do

    random_key = katas.keys.sample
    kata = katas[random_key]
    show_kata = "#{kata["name"]} \nYour task: #{kata["description"]}\nKata key: #{random_key}"

    chatop_send show_kata
  end

  chatop :hint,
    /hint (?<kata_key>.+)/,
    "hint kata_key - Get a hint to solve your ops kata" do
      kata_key = jsonrpc_params.require(:kata_key)
      kata = katas[kata_key]
      show_kata = "Your hint: #{kata["hint"]}"

      chatop_send show_kata
    end

  chatop :solution,
    /solution (?<kata_key>.+)/,
    "solution kata_key - Get a solution of your ops kata" do
      kata_key = jsonrpc_params.require(:kata_key)
      kata = katas[kata_key]
      show_kata = "Your solution: #{kata["solution"]}"

      chatop_send show_kata
    end
end
