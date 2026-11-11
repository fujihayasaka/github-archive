# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class CopilotChatEvals < Seeds::Runner
      include GitHub::Memoizer

      sig { returns String }
      def self.help
        <<~HELP
        Seed data for Copilot Chat outcome-based evaluation hero scenarios.
        Creates repos, PRs, issues, and files in the copilot-eval org that the
        11 hero evaluation scenarios reference. Runs on top of script/enable-copilot-chat.
        HELP
      end

      sig { params(options: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def self.run(options = {})
        require_relative "../factory_bot_loader"

        new.run(options)
      end

      sig { params(options: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def run(options)
        create_org
        create_repositories
        create_pull_requests
        create_issues
        print_summary
      rescue Faraday::ConnectionFailed
        warn "Your github/github server is not running. Please start it with ./script/server and try again."
        exit 1
      end

      private

      # ─── Organisation ──────────────────────────────────────────────

      sig { void }
      def create_org
        puts "➡️  Creating copilot-eval organisation..."
        copilot_eval_org
        puts "➡️  Done creating copilot-eval organisation!"
      end

      memoize def copilot_eval_org
        org_login = "copilot-eval"
        org = Organization.find_by(login: org_login)
        if org
          puts "  Found @#{org_login}"
        else
          puts "  Creating @#{org_login}..."
          org = Seeds::Objects::Organization.create(login: org_login, admin: monalisa)
        end
        org
      end

      # ─── Users ─────────────────────────────────────────────────────

      memoize def monalisa
        Seeds::Objects::User.monalisa
      end

      # ─── Repositories ──────────────────────────────────────────────

      sig { void }
      def create_repositories
        puts "➡️  Creating repositories..."
        ui_app_repo
        main_app_repo
        eval_tests_repo
        browser_app_repo
        api_service_repo
        codeql_tool_repo
        puts "➡️  Done creating repositories!"
      end

      # -- copilot-eval/ui-app (scenarios 1, 3) --

      memoize def ui_app_repo
        repo = find_or_create_repo("ui-app")
        seed_ui_app(repo)
        repo
      end

      def seed_ui_app(repo)
        puts "  Seeding copilot-eval/ui-app..."

        # Base files on default branch
        Seeds::Objects::Commit.create(
          repo: repo,
          message: "Initial project structure",
          committer: monalisa,
          files: {
            "package.json" => <<~JSON,
              {
                "name": "ui-app",
                "version": "1.0.0",
                "private": true,
                "dependencies": {
                  "react": "^18.2.0",
                  "react-dom": "^18.2.0"
                }
              }
            JSON
            "src/App.tsx" => <<~TSX,
              import React from "react";
              import { ResourcePanel } from "./components/ResourcePanel";

              export default function App() {
                return (
                  <div className="app">
                    <h1>UI App</h1>
                    <ResourcePanel />
                  </div>
                );
              }
            TSX
            "src/components/ResourcePanel.tsx" => <<~TSX,
              import React from "react";

              export function ResourcePanel() {
                return <div className="resource-panel">Resources</div>;
              }
            TSX
            # Scenario 3: exact string that the eval searches for
            "src/pages/SpacesInfo.tsx" => <<~TSX,
              import React from "react";

              export default function SpacesInfo() {
                return (
                  <div className="spaces-info">
                    <p>Spaces are available in VSCode! Get started using Spaces with the GitHub MCP server.</p>
                  </div>
                );
              }
            TSX
            "src/index.tsx" => <<~TSX,
              import React from "react";
              import ReactDOM from "react-dom/client";
              import App from "./App";

              const root = ReactDOM.createRoot(document.getElementById("root")!);
              root.render(<App />);
            TSX
          },
        )

        # Scenario 1: PR branch that introduces a feature flag
        Seeds::Objects::Commit.create(
          repo: repo,
          message: "Add resource panel gated behind feature flag",
          committer: monalisa,
          branch_name: "feature/resource-panel",
          from_branch: repo.default_branch,
          files: {
            "src/components/ResourcePanel.tsx" => <<~TSX,
              import React from "react";
              import { useFeatureFlag } from "../hooks/useFeatureFlag";

              export function ResourcePanel() {
                const isEnabled = useFeatureFlag("copilot_resource_panel");

                if (!isEnabled) {
                  return null;
                }

                return (
                  <div className="resource-panel">
                    <h2>Resources</h2>
                    <ul>
                      <li>Documentation</li>
                      <li>API Reference</li>
                      <li>Tutorials</li>
                    </ul>
                  </div>
                );
              }
            TSX
            "src/hooks/useFeatureFlag.ts" => <<~TS,
              import { useState, useEffect } from "react";

              export function useFeatureFlag(flagName: string): boolean {
                const [enabled, setEnabled] = useState(false);

                useEffect(() => {
                  fetch(\`/api/feature-flags/\${flagName}\`)
                    .then((res) => res.json())
                    .then((data) => setEnabled(data.enabled))
                    .catch(() => setEnabled(false));
                }, [flagName]);

                return enabled;
              }
            TS
          },
        )
      end

      # -- copilot-eval/main-app (scenario 2) --

      memoize def main_app_repo
        repo = find_or_create_repo("main-app")
        seed_main_app(repo)
        repo
      end

      def seed_main_app(repo)
        puts "  Seeding copilot-eval/main-app..."

        Seeds::Objects::Commit.create(
          repo: repo,
          message: "Initial Rails application structure",
          committer: monalisa,
          files: {
            "app/models/user.rb" => <<~RUBY,
              class User < ApplicationRecord
                has_many :posts
                validates :email, presence: true, uniqueness: true
              end
            RUBY
            "app/models/post.rb" => <<~RUBY,
              class Post < ApplicationRecord
                belongs_to :user
                validates :title, :body, presence: true
              end
            RUBY
            "app/controllers/application_controller.rb" => <<~RUBY,
              class ApplicationController < ActionController::Base
                before_action :authenticate_user!
              end
            RUBY
            "app/controllers/posts_controller.rb" => <<~RUBY,
              class PostsController < ApplicationController
                def index
                  @posts = Post.all
                end

                def show
                  @post = Post.find(params[:id])
                end
              end
            RUBY
            "app/views/layouts/application.html.erb" => <<~ERB,
              <!DOCTYPE html>
              <html>
              <head><title>MainApp</title></head>
              <body><%= yield %></body>
              </html>
            ERB
            "app/views/posts/index.html.erb" => <<~ERB,
              <h1>Posts</h1>
              <% @posts.each do |post| %>
                <p><%= post.title %></p>
              <% end %>
            ERB
            "lib/tasks/seed.rake" => <<~RUBY,
              namespace :db do
                task seed: :environment do
                  puts "Seeding database..."
                end
              end
            RUBY
            "config/routes.rb" => <<~RUBY,
              Rails.application.routes.draw do
                resources :posts
                root "posts#index"
              end
            RUBY
            "config/database.yml" => <<~YAML,
              default: &default
                adapter: postgresql
                pool: 5
              development:
                <<: *default
                database: main_app_development
            YAML
            "test/models/user_test.rb" => <<~RUBY,
              require "test_helper"

              class UserTest < ActiveSupport::TestCase
                test "should not save user without email" do
                  user = User.new
                  assert_not user.save
                end
              end
            RUBY
            "test/controllers/posts_controller_test.rb" => <<~RUBY,
              require "test_helper"

              class PostsControllerTest < ActionDispatch::IntegrationTest
                test "should get index" do
                  get posts_url
                  assert_response :success
                end
              end
            RUBY
            "script/setup.sh" => <<~SH,
              #!/bin/bash
              bundle install
              rails db:create db:migrate db:seed
            SH
            "db/migrations/001_create_users.rb" => <<~RUBY,
              class CreateUsers < ActiveRecord::Migration[7.0]
                def change
                  create_table :users do |t|
                    t.string :email, null: false
                    t.string :name
                    t.timestamps
                  end
                end
              end
            RUBY
            "db/migrations/002_create_posts.rb" => <<~RUBY,
              class CreatePosts < ActiveRecord::Migration[7.0]
                def change
                  create_table :posts do |t|
                    t.references :user, foreign_key: true
                    t.string :title, null: false
                    t.text :body, null: false
                    t.timestamps
                  end
                end
              end
            RUBY
            "public/favicon.ico" => "",
            "public/robots.txt" => "User-agent: *\nDisallow: /admin\n",
            "Gemfile" => <<~GEM,
              source "https://rubygems.org"
              gem "rails", "~> 7.0"
              gem "pg"
            GEM
            "README.md" => <<~MD,
              # Main App

              A Rails application with users and posts.

              ## Setup

              ```
              ./script/setup.sh
              ```
            MD
          },
        )
      end

      # -- copilot-eval/eval-tests (scenario 4) --

      memoize def eval_tests_repo
        repo = find_or_create_repo("eval-tests")
        seed_eval_tests(repo)
        repo
      end

      def seed_eval_tests(repo)
        puts "  Seeding copilot-eval/eval-tests..."

        Seeds::Objects::Commit.create(
          repo: repo,
          message: "Add benchmark test scenarios and skill definitions",
          committer: monalisa,
          files: {
            "benchmarks/chat/scenarios.yaml" => <<~YAML,
              scenarios:
                - id: scenario-feature-flag-from-pr
                  name: Feature Flag from PR
                  category: code_search
                  prompt: "What is the name of the feature flag that controls this feature?"
                  expected_outcome: "Identifies copilot_resource_panel as the feature flag"
                  priority: p0

                - id: scenario-file-tree-github
                  name: File Tree
                  category: code_search
                  prompt: "Show me the file tree for this repo"
                  expected_outcome: "Renders complete directory tree"
                  priority: p0

                - id: scenario-find-content-implementation
                  name: Find Content Implementation
                  category: code_search
                  prompt: "find where the line of content is implemented"
                  expected_outcome: "Locates the file containing the target string"
                  priority: p0

                - id: scenario-list-test-cases-structured
                  name: List Test Cases
                  category: code_search
                  prompt: "list all the test cases in a clean format"
                  expected_outcome: "Returns structured list of test case definitions"
                  priority: p0

                - id: scenario-architecture-diagram
                  name: Architecture Diagram
                  category: code_search
                  prompt: "Give me an architecture diagram of this repo"
                  expected_outcome: "Generates diagram showing major components"
                  priority: p0

                - id: scenario-find-system-prompt-with-repo
                  name: Find System Prompt
                  category: find_in_github
                  prompt: "Where is the Copilot Chat system prompt?"
                  expected_outcome: "Locates system prompt definition file"
                  priority: p0

                - id: scenario-find-issues-assigned-to-me
                  name: Find Assigned Issues
                  category: find_in_github
                  prompt: "What issues are assigned to me?"
                  expected_outcome: "Lists issues assigned to the current user"
                  priority: p0

                - id: scenario-pr-from-code-search
                  name: PR from Code Search
                  category: code_authoring
                  prompt: "Find where HTTP routes are defined and create a PR that adds a health check endpoint"
                  expected_outcome: "Creates a working PR with health check route"
                  priority: p0

                - id: scenario-pr-merge-sort-with-repo
                  name: PR Merge Sort
                  category: code_authoring
                  prompt: "Create a PR to help me implement a merge sort algorithm in Go"
                  expected_outcome: "Creates PR with correct merge sort implementation"
                  priority: p0

                - id: scenario-pr-from-issue
                  name: PR from Issue
                  category: code_authoring
                  prompt: "Create a PR to address this issue"
                  expected_outcome: "Creates PR that fixes the described issue"
                  priority: p0

                - id: scenario-nodejs-latest-version
                  name: Node.js Latest Version
                  category: web_search
                  prompt: "What is the latest LTS version of Node.js?"
                  expected_outcome: "Returns current Node.js LTS version"
                  priority: p0
            YAML
            "benchmarks/chat/skills.yaml" => <<~YAML,
              skills:
                - id: code-search
                  name: Code Search
                  description: Searches across repository code to find relevant files
                  scenarios:
                    - scenario-feature-flag-from-pr
                    - scenario-file-tree-github
                    - scenario-find-content-implementation
                    - scenario-list-test-cases-structured
                    - scenario-architecture-diagram

                - id: find-in-github
                  name: Find in GitHub
                  description: Finds GitHub-specific resources like issues, PRs, and repos
                  scenarios:
                    - scenario-find-system-prompt-with-repo
                    - scenario-find-issues-assigned-to-me

                - id: code-authoring
                  name: Code Authoring
                  description: Creates pull requests with code changes
                  scenarios:
                    - scenario-pr-from-code-search
                    - scenario-pr-merge-sort-with-repo
                    - scenario-pr-from-issue

                - id: web-search
                  name: Web Search
                  description: Searches the web for current information
                  scenarios:
                    - scenario-nodejs-latest-version
            YAML
            "README.md" => <<~MD,
              # Copilot Chat Evaluation Tests

              This repository contains benchmark scenarios and skill definitions for
              evaluating Copilot Chat response quality.

              ## Structure

              - `benchmarks/chat/scenarios.yaml` — Hero test scenario definitions
              - `benchmarks/chat/skills.yaml` — Skill-to-scenario mappings
            MD
          },
        )
      end

      # -- copilot-eval/browser-app (scenario 5) --

      memoize def browser_app_repo
        repo = find_or_create_repo("browser-app")
        seed_browser_app(repo)
        repo
      end

      def seed_browser_app(repo)
        puts "  Seeding copilot-eval/browser-app..."

        Seeds::Objects::Commit.create(
          repo: repo,
          message: "Initial browser engine architecture",
          committer: monalisa,
          files: {
            "src/renderer/layout.rs" => <<~RUST,
              use crate::dom::Node;

              pub struct LayoutBox {
                  pub dimensions: Dimensions,
                  pub box_type: BoxType,
                  pub children: Vec<LayoutBox>,
              }

              pub struct Dimensions {
                  pub content: Rect,
                  pub padding: EdgeSizes,
                  pub margin: EdgeSizes,
              }

              pub struct Rect {
                  pub x: f32,
                  pub y: f32,
                  pub width: f32,
                  pub height: f32,
              }

              pub struct EdgeSizes {
                  pub top: f32,
                  pub right: f32,
                  pub bottom: f32,
                  pub left: f32,
              }

              pub enum BoxType {
                  Block,
                  Inline,
                  Anonymous,
              }

              impl LayoutBox {
                  pub fn layout(&mut self, containing_block: &Dimensions) {
                      match self.box_type {
                          BoxType::Block => self.layout_block(containing_block),
                          BoxType::Inline | BoxType::Anonymous => {}
                      }
                  }

                  fn layout_block(&mut self, containing_block: &Dimensions) {
                      self.calculate_width(containing_block);
                      self.calculate_position(containing_block);
                      self.layout_children();
                      self.calculate_height();
                  }

                  fn calculate_width(&mut self, _containing_block: &Dimensions) {}
                  fn calculate_position(&mut self, _containing_block: &Dimensions) {}
                  fn layout_children(&mut self) {}
                  fn calculate_height(&mut self) {}
              }
            RUST
            "src/renderer/paint.rs" => <<~RUST,
              use crate::renderer::layout::LayoutBox;

              pub struct Canvas {
                  pub pixels: Vec<Color>,
                  pub width: usize,
                  pub height: usize,
              }

              #[derive(Clone, Copy)]
              pub struct Color {
                  pub r: u8,
                  pub g: u8,
                  pub b: u8,
                  pub a: u8,
              }

              impl Canvas {
                  pub fn new(width: usize, height: usize) -> Canvas {
                      Canvas {
                          pixels: vec![Color { r: 255, g: 255, b: 255, a: 255 }; width * height],
                          width,
                          height,
                      }
                  }

                  pub fn paint(&mut self, layout_root: &LayoutBox) {
                      let display_list = build_display_list(layout_root);
                      for item in display_list {
                          self.render_item(&item);
                      }
                  }

                  fn render_item(&mut self, _item: &DisplayCommand) {}
              }

              enum DisplayCommand {
                  SolidColor(Color, f32, f32, f32, f32),
              }

              fn build_display_list(_root: &LayoutBox) -> Vec<DisplayCommand> {
                  Vec::new()
              }
            RUST
            "src/networking/http.rs" => <<~RUST,
              use std::collections::HashMap;

              pub struct HttpClient {
                  cache: HashMap<String, CachedResponse>,
              }

              pub struct HttpRequest {
                  pub method: Method,
                  pub url: String,
                  pub headers: HashMap<String, String>,
                  pub body: Option<Vec<u8>>,
              }

              pub struct HttpResponse {
                  pub status: u16,
                  pub headers: HashMap<String, String>,
                  pub body: Vec<u8>,
              }

              struct CachedResponse {
                  response: HttpResponse,
                  expires_at: std::time::Instant,
              }

              pub enum Method {
                  Get,
                  Post,
                  Put,
                  Delete,
              }

              impl HttpClient {
                  pub fn new() -> Self {
                      HttpClient { cache: HashMap::new() }
                  }

                  pub fn send(&mut self, request: HttpRequest) -> Result<HttpResponse, String> {
                      if let Some(cached) = self.cache.get(&request.url) {
                          if cached.expires_at > std::time::Instant::now() {
                              return Ok(HttpResponse {
                                  status: cached.response.status,
                                  headers: cached.response.headers.clone(),
                                  body: cached.response.body.clone(),
                              });
                          }
                      }
                      Err("Network request not implemented".to_string())
                  }
              }
            RUST
            "src/networking/dns.rs" => <<~RUST,
              use std::collections::HashMap;
              use std::net::IpAddr;

              pub struct DnsResolver {
                  cache: HashMap<String, DnsRecord>,
              }

              pub struct DnsRecord {
                  pub address: IpAddr,
                  pub ttl: u32,
              }

              impl DnsResolver {
                  pub fn new() -> Self {
                      DnsResolver { cache: HashMap::new() }
                  }

                  pub fn resolve(&mut self, hostname: &str) -> Result<IpAddr, String> {
                      if let Some(record) = self.cache.get(hostname) {
                          return Ok(record.address);
                      }
                      Err(format!("Could not resolve {}", hostname))
                  }
              }
            RUST
            "src/dom/node.rs" => <<~RUST,
              use std::collections::HashMap;

              pub struct Node {
                  pub children: Vec<Node>,
                  pub node_type: NodeType,
              }

              pub enum NodeType {
                  Text(String),
                  Element(ElementData),
                  Comment(String),
              }

              pub struct ElementData {
                  pub tag_name: String,
                  pub attributes: HashMap<String, String>,
              }

              impl Node {
                  pub fn text(data: String) -> Node {
                      Node { children: Vec::new(), node_type: NodeType::Text(data) }
                  }

                  pub fn element(tag: String, attrs: HashMap<String, String>, children: Vec<Node>) -> Node {
                      Node {
                          children,
                          node_type: NodeType::Element(ElementData {
                              tag_name: tag,
                              attributes: attrs,
                          }),
                      }
                  }
              }
            RUST
            "src/dom/parser.rs" => <<~RUST,
              use crate::dom::node::{Node, ElementData, NodeType};

              pub struct HtmlParser {
                  pos: usize,
                  input: String,
              }

              impl HtmlParser {
                  pub fn new(input: String) -> Self {
                      HtmlParser { pos: 0, input }
                  }

                  pub fn parse(&mut self) -> Node {
                      let mut nodes = self.parse_nodes();
                      if nodes.len() == 1 {
                          nodes.remove(0)
                      } else {
                          Node::element("html".to_string(), std::collections::HashMap::new(), nodes)
                      }
                  }

                  fn parse_nodes(&mut self) -> Vec<Node> {
                      let mut nodes = Vec::new();
                      loop {
                          self.consume_whitespace();
                          if self.eof() || self.starts_with("</") {
                              break;
                          }
                          nodes.push(self.parse_node());
                      }
                      nodes
                  }

                  fn parse_node(&mut self) -> Node {
                      if self.starts_with("<") {
                          self.parse_element()
                      } else {
                          self.parse_text()
                      }
                  }

                  fn parse_text(&mut self) -> Node {
                      Node::text(self.consume_while(|c| c != '<'))
                  }

                  fn parse_element(&mut self) -> Node {
                      Node::element("div".to_string(), std::collections::HashMap::new(), Vec::new())
                  }

                  fn consume_whitespace(&mut self) {
                      self.consume_while(|c| c.is_whitespace());
                  }

                  fn consume_while<F: Fn(char) -> bool>(&mut self, test: F) -> String {
                      let mut result = String::new();
                      while !self.eof() && test(self.next_char()) {
                          result.push(self.consume_char());
                      }
                      result
                  }

                  fn consume_char(&mut self) -> char {
                      let c = self.input[self.pos..].chars().next().unwrap();
                      self.pos += c.len_utf8();
                      c
                  }

                  fn next_char(&self) -> char {
                      self.input[self.pos..].chars().next().unwrap()
                  }

                  fn eof(&self) -> bool {
                      self.pos >= self.input.len()
                  }

                  fn starts_with(&self, s: &str) -> bool {
                      self.input[self.pos..].starts_with(s)
                  }
              }
            RUST
            "src/js_engine/interpreter.rs" => <<~RUST,
              use std::collections::HashMap;

              pub struct Interpreter {
                  global_scope: Scope,
              }

              pub struct Scope {
                  variables: HashMap<String, JsValue>,
                  parent: Option<Box<Scope>>,
              }

              #[derive(Clone, Debug)]
              pub enum JsValue {
                  Undefined,
                  Null,
                  Boolean(bool),
                  Number(f64),
                  Str(String),
                  Object(HashMap<String, JsValue>),
              }

              impl Interpreter {
                  pub fn new() -> Self {
                      Interpreter {
                          global_scope: Scope {
                              variables: HashMap::new(),
                              parent: None,
                          },
                      }
                  }

                  pub fn execute(&mut self, _source: &str) -> JsValue {
                      JsValue::Undefined
                  }

                  pub fn get_variable(&self, name: &str) -> Option<&JsValue> {
                      self.global_scope.variables.get(name)
                  }

                  pub fn set_variable(&mut self, name: String, value: JsValue) {
                      self.global_scope.variables.insert(name, value);
                  }
              }
            RUST
            "src/js_engine/lexer.rs" => <<~RUST,
              #[derive(Debug, Clone, PartialEq)]
              pub enum Token {
                  Identifier(String),
                  Number(f64),
                  StringLiteral(String),
                  LeftParen,
                  RightParen,
                  LeftBrace,
                  RightBrace,
                  Semicolon,
                  Equals,
                  Plus,
                  Minus,
                  Star,
                  Slash,
                  Let,
                  Const,
                  Function,
                  Return,
                  If,
                  Else,
                  Eof,
              }

              pub struct Lexer {
                  input: Vec<char>,
                  pos: usize,
              }

              impl Lexer {
                  pub fn new(input: &str) -> Self {
                      Lexer { input: input.chars().collect(), pos: 0 }
                  }

                  pub fn tokenize(&mut self) -> Vec<Token> {
                      let mut tokens = Vec::new();
                      while self.pos < self.input.len() {
                          self.skip_whitespace();
                          if self.pos >= self.input.len() { break; }
                          let token = self.next_token();
                          tokens.push(token);
                      }
                      tokens.push(Token::Eof);
                      tokens
                  }

                  fn next_token(&mut self) -> Token {
                      let ch = self.input[self.pos];
                      self.pos += 1;
                      match ch {
                          '(' => Token::LeftParen,
                          ')' => Token::RightParen,
                          '{' => Token::LeftBrace,
                          '}' => Token::RightBrace,
                          ';' => Token::Semicolon,
                          '=' => Token::Equals,
                          '+' => Token::Plus,
                          '-' => Token::Minus,
                          '*' => Token::Star,
                          '/' => Token::Slash,
                          _ => Token::Eof,
                      }
                  }

                  fn skip_whitespace(&mut self) {
                      while self.pos < self.input.len() && self.input[self.pos].is_whitespace() {
                          self.pos += 1;
                      }
                  }
              }
            RUST
            "src/main.rs" => <<~RUST,
              mod dom;
              mod js_engine;
              mod networking;
              mod renderer;

              fn main() {
                  println!("Browser engine starting...");
              }
            RUST
            "Cargo.toml" => <<~TOML,
              [package]
              name = "browser-app"
              version = "0.1.0"
              edition = "2021"

              [dependencies]
            TOML
            "README.md" => <<~MD,
              # Browser App

              A toy browser engine written in Rust.

              ## Architecture

              - `src/renderer/` — Layout engine and painting
              - `src/networking/` — HTTP client and DNS resolver
              - `src/dom/` — DOM tree and HTML parser
              - `src/js_engine/` — JavaScript interpreter and lexer
            MD
          },
        )
      end

      # -- copilot-eval/api-service (scenarios 6, 7, 8, 9) --

      memoize def api_service_repo
        repo = find_or_create_repo("api-service")
        seed_api_service(repo)
        repo
      end

      def seed_api_service(repo)
        puts "  Seeding copilot-eval/api-service..."

        Seeds::Objects::Commit.create(
          repo: repo,
          message: "Initial Go API service",
          committer: monalisa,
          files: {
            "go.mod" => <<~MOD,
              module github.com/copilot-eval/api-service

              go 1.21
            MOD
            "cmd/server/main.go" => <<~GO,
              package main

              import (
              	"fmt"
              	"log"
              	"net/http"

              	"github.com/copilot-eval/api-service/internal/routes"
              )

              func main() {
              	router := routes.NewRouter()
              	fmt.Println("Starting server on :8080")
              	log.Fatal(http.ListenAndServe(":8080", router))
              }
            GO
            # Scenario 8: route definitions for the eval to find and extend
            "internal/routes/routes.go" => <<~GO,
              package routes

              import (
              	"encoding/json"
              	"net/http"
              )

              type Router struct {
              	mux *http.ServeMux
              }

              func NewRouter() *Router {
              	r := &Router{mux: http.NewServeMux()}
              	r.registerRoutes()
              	return r
              }

              func (r *Router) ServeHTTP(w http.ResponseWriter, req *http.Request) {
              	r.mux.ServeHTTP(w, req)
              }

              func (r *Router) registerRoutes() {
              	r.mux.HandleFunc("/api/v1/users", r.handleUsers)
              	r.mux.HandleFunc("/api/v1/repos", r.handleRepos)
              	r.mux.HandleFunc("/api/v1/search", r.handleSearch)
              }

              func (r *Router) handleUsers(w http.ResponseWriter, req *http.Request) {
              	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "resource": "users"})
              }

              func (r *Router) handleRepos(w http.ResponseWriter, req *http.Request) {
              	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "resource": "repos"})
              }

              func (r *Router) handleSearch(w http.ResponseWriter, req *http.Request) {
              	query := req.URL.Query().Get("q")
              	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "query": query})
              }
            GO
            # Scenario 6: system prompt file
            "pkg/prompt/system_prompt.go" => <<~GO,
              package prompt

              // SystemPrompt returns the default system prompt used by Copilot Chat.
              const SystemPrompt = `You are an AI programming assistant called GitHub Copilot.
              When asked for your name, you must respond with "GitHub Copilot".
              Follow the user's requirements carefully and to the letter.
              Your expertise is strictly limited to software development topics.
              For questions not related to software development, simply give a reminder
              that you are an AI programming assistant.
              Keep your answers short and impersonal.
              You use the GPT-4 version of OpenAI's GPT models.
              You can only give one reply for each conversation turn.`

              // BuildSystemPrompt constructs the full system prompt with context injections.
              func BuildSystemPrompt(context map[string]string) string {
              	prompt := SystemPrompt
              	if repo, ok := context["repository"]; ok {
              		prompt += "\\nThe user is working in the repository: " + repo
              	}
              	if lang, ok := context["language"]; ok {
              		prompt += "\\nThe primary language is: " + lang
              	}
              	return prompt
              }
            GO
            # Scenario 6: config referencing the prompt
            "internal/config/prompts.yaml" => <<~YAML,
              prompts:
                system:
                  source: pkg/prompt/system_prompt.go
                  version: "2.1"
                  max_tokens: 4096
                  description: "Default system prompt for Copilot Chat"
                skills:
                  code_search:
                    temperature: 0.1
                    max_tokens: 2048
                  code_authoring:
                    temperature: 0.3
                    max_tokens: 4096
            YAML
            "internal/config/config.go" => <<~GO,
              package config

              import "os"

              type Config struct {
              	Port        string
              	DatabaseURL string
              	LogLevel    string
              }

              func Load() *Config {
              	return &Config{
              		Port:        getEnv("PORT", "8080"),
              		DatabaseURL: getEnv("DATABASE_URL", "postgres://localhost/api_service"),
              		LogLevel:    getEnv("LOG_LEVEL", "info"),
              	}
              }

              func getEnv(key, fallback string) string {
              	if value, ok := os.LookupEnv(key); ok {
              		return value
              	}
              	return fallback
              }
            GO
            "README.md" => <<~MD,
              # API Service

              A Go-based API service for Copilot.

              ## Running

              ```
              go run cmd/server/main.go
              ```

              ## Routes

              - `GET /api/v1/users` — List users
              - `GET /api/v1/repos` — List repositories
              - `GET /api/v1/search?q=term` — Search
            MD
          },
        )
      end

      # -- copilot-eval/codeql-tool (scenario 10) --

      memoize def codeql_tool_repo
        repo = find_or_create_repo("codeql-tool")
        seed_codeql_tool(repo)
        repo
      end

      def seed_codeql_tool(repo)
        puts "  Seeding copilot-eval/codeql-tool..."

        Seeds::Objects::Commit.create(
          repo: repo,
          message: "Initial CodeQL analysis tool",
          committer: monalisa,
          files: {
            "go.mod" => <<~MOD,
              module github.com/copilot-eval/codeql-tool

              go 1.21
            MOD
            "cmd/analyze/main.go" => <<~GO,
              package main

              import (
              	"fmt"
              	"os"

              	"github.com/copilot-eval/codeql-tool/internal/runner"
              )

              func main() {
              	if len(os.Args) < 2 {
              		fmt.Fprintln(os.Stderr, "Usage: analyze <path>")
              		os.Exit(1)
              	}
              	r := runner.New()
              	results, err := r.Analyze(os.Args[1])
              	if err != nil {
              		fmt.Fprintf(os.Stderr, "Analysis failed: %v\\n", err)
              		os.Exit(1)
              	}
              	for _, result := range results {
              		fmt.Printf("[%s] %s:%d — %s\\n", result.Severity, result.File, result.Line, result.Message)
              	}
              }
            GO
            # Code with the nil pointer bug described in the issue
            "internal/runner/runner.go" => <<~GO,
              package runner

              import (
              	"os"
              	"path/filepath"
              )

              type Runner struct {
              	config *Config
              }

              type Config struct {
              	RulesDir string
              	MaxDepth int
              }

              type AnalysisResult struct {
              	File     string
              	Line     int
              	Severity string
              	Message  string
              }

              func New() *Runner {
              	return &Runner{}
              }

              // Analyze runs the analysis on the given path.
              // BUG: config is not initialized, leading to nil pointer dereference
              // when accessing config.RulesDir or config.MaxDepth.
              func (r *Runner) Analyze(path string) ([]AnalysisResult, error) {
              	// This will panic with nil pointer dereference because r.config is nil
              	rulesDir := r.config.RulesDir
              	files, err := collectFiles(path, r.config.MaxDepth)
              	if err != nil {
              		return nil, err
              	}

              	var results []AnalysisResult
              	for _, file := range files {
              		fileResults := analyzeFile(file, rulesDir)
              		results = append(results, fileResults...)
              	}
              	return results, nil
              }

              func collectFiles(root string, maxDepth int) ([]string, error) {
              	var files []string
              	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
              		if err != nil {
              			return err
              		}
              		if !d.IsDir() {
              			files = append(files, path)
              		}
              		return nil
              	})
              	return files, err
              }

              func analyzeFile(path string, rulesDir string) []AnalysisResult {
              	return nil
              }
            GO
            "internal/runner/runner_test.go" => <<~GO,
              package runner

              import "testing"

              func TestNewRunner(t *testing.T) {
              	r := New()
              	if r == nil {
              		t.Fatal("expected non-nil runner")
              	}
              }

              func TestAnalyze_NilConfig(t *testing.T) {
              	r := New()
              	// This test demonstrates the nil pointer bug:
              	// r.config is nil, so calling Analyze will panic.
              	defer func() {
              		if recover() == nil {
              			t.Fatal("expected panic from nil config")
              		}
              	}()
              	r.Analyze(".")
              }
            GO
            "README.md" => <<~MD,
              # CodeQL Tool

              A static analysis tool for Go codebases.

              ## Usage

              ```
              go run cmd/analyze/main.go <path>
              ```
            MD
          },
        )
      end

      # ─── Pull Requests ─────────────────────────────────────────────

      sig { void }
      def create_pull_requests
        puts "➡️  Creating pull requests..."
        create_resource_panel_pr
        puts "➡️  Done creating pull requests!"
      end

      def create_resource_panel_pr
        repo = ui_app_repo
        head_branch = "feature/resource-panel"

        existing_pr = PullRequest.find_open_based_on_ref(repo, head_branch).first
        if existing_pr
          puts "  PR already exists for #{head_branch}, closing to recreate..."
          existing_pr.close(monalisa)
        end

        puts "  Creating PR: Add resource panel feature flag..."
        ::PullRequest.create_for!(repo,
          user: monalisa,
          title: "Add resource panel gated behind copilot_resource_panel feature flag",
          body: <<~BODY,
            This PR introduces the `ResourcePanel` component, gated behind the
            `copilot_resource_panel` feature flag.

            Changes:
            - Updated `ResourcePanel` to check the `copilot_resource_panel` flag
            - Added `useFeatureFlag` hook for runtime flag evaluation
          BODY
          head: head_branch,
          base: repo.default_branch,
        )
      end

      # ─── Issues ────────────────────────────────────────────────────

      sig { void }
      def create_issues
        puts "➡️  Creating issues..."
        create_api_service_issues
        create_codeql_tool_issue
        puts "➡️  Done creating issues!"
      end

      def create_api_service_issues
        repo = api_service_repo
        issues_data = [
          {
            title: "Add rate limiting to API endpoints",
            body: "We need to implement rate limiting on all `/api/v1/*` endpoints to prevent abuse. " \
                  "Consider using a token bucket algorithm with configurable limits per API key.",
          },
          {
            title: "Implement structured logging with request tracing",
            body: "Replace `fmt.Println` calls with structured logging using `slog`. " \
                  "Each request should have a unique trace ID propagated through the context.",
          },
          {
            title: "Add pagination support to list endpoints",
            body: "The `/api/v1/users` and `/api/v1/repos` endpoints return all records. " \
                  "Add cursor-based pagination with `?cursor=` and `?limit=` query parameters.",
          },
          {
            title: "Write integration tests for search endpoint",
            body: "The search endpoint at `/api/v1/search` has no test coverage. " \
                  "Add integration tests covering empty queries, special characters, and large result sets.",
          },
          {
            title: "Add OpenAPI specification",
            body: "Generate an OpenAPI 3.0 spec for all API endpoints. " \
                  "Include request/response schemas, error codes, and authentication requirements.",
          },
        ]

        issues_data.each do |issue_data|
          existing = repo.issues.where(title: issue_data[:title]).first
          if existing
            puts "  Issue already exists: #{issue_data[:title]}"
          else
            puts "  Creating issue: #{issue_data[:title]}"
            Seeds::Objects::Issue.create(
              repo: repo,
              actor: monalisa,
              title: issue_data[:title],
              body: issue_data[:body],
              assignees: [monalisa],
            )
          end
        end
      end

      def create_codeql_tool_issue
        repo = codeql_tool_repo
        title = "Fix nil pointer dereference in analysis runner"

        existing = repo.issues.where(title: title).first
        if existing
          puts "  Issue already exists: #{title}"
        else
          puts "  Creating issue: #{title}"
          Seeds::Objects::Issue.create(
            repo: repo,
            actor: monalisa,
            title: title,
            body: <<~BODY,
              ## Bug Report

              The `Runner.Analyze()` method in `internal/runner/runner.go` panics with a nil
              pointer dereference when called because `Runner.config` is never initialized.

              ### Steps to Reproduce

              ```go
              r := runner.New()
              results, err := r.Analyze(".")  // panics here
              ```

              ### Expected Behavior

              `Analyze` should either:
              1. Initialize `config` with sensible defaults in `New()`, or
              2. Return an error if `config` is nil

              ### Actual Behavior

              Panics at `r.config.RulesDir` because `r.config` is `nil`.

              ### Suggested Fix

              Update `New()` to initialize the config with defaults:

              ```go
              func New() *Runner {
                  return &Runner{
                      config: &Config{
                          RulesDir: "rules/",
                          MaxDepth: 10,
                      },
                  }
              }
              ```
            BODY
            assignees: [monalisa],
          )
        end
      end

      # ─── Helpers ───────────────────────────────────────────────────

      def find_or_create_repo(name)
        nwo = "copilot-eval/#{name}"
        repo = ::Repository.nwo(nwo)
        if repo
          puts "  Found repository #{nwo}"
          repo.setup_git_repository
          return repo
        end

        puts "  Creating repository #{nwo}..."
        Seeds::Objects::Repository.create_with_nwo(nwo: nwo, setup_master: true)
      end

      # ─── Summary ───────────────────────────────────────────────────

      def print_summary
        puts ""
        puts "=" * 60
        puts "✅ Copilot Chat Eval seed data created successfully!"
        puts "=" * 60
        puts ""
        puts "Repositories:"
        %w[ui-app main-app eval-tests browser-app api-service codeql-tool].each do |name|
          puts "  📦 http://github.localhost/copilot-eval/#{name}"
        end
        puts ""
        puts "Pull Requests:"
        puts "  🔀 http://github.localhost/copilot-eval/ui-app/pulls"
        puts ""
        puts "Issues:"
        puts "  📋 http://github.localhost/copilot-eval/api-service/issues"
        puts "  📋 http://github.localhost/copilot-eval/codeql-tool/issues"
        puts ""
        puts "Hero scenarios covered:"
        puts "  1. scenario-feature-flag-from-pr    → copilot-eval/ui-app PR"
        puts "  2. scenario-file-tree-github         → copilot-eval/main-app"
        puts "  3. scenario-find-content-implementation → copilot-eval/ui-app"
        puts "  4. scenario-list-test-cases-structured → copilot-eval/eval-tests"
        puts "  5. scenario-architecture-diagram      → copilot-eval/browser-app"
        puts "  6. scenario-find-system-prompt-with-repo → copilot-eval/api-service"
        puts "  7. scenario-find-issues-assigned-to-me → copilot-eval/api-service"
        puts "  8. scenario-pr-from-code-search       → copilot-eval/api-service"
        puts "  9. scenario-pr-merge-sort-with-repo   → copilot-eval/api-service"
        puts " 10. scenario-pr-from-issue             → copilot-eval/codeql-tool"
        puts " 11. scenario-nodejs-latest-version     → (no seed data needed)"
        puts ""
      end
    end
  end
end
