# typed: true
# frozen_string_literal: true

# Usage:
# `bin/safe-ruby script/validate_models_docs_content.rb`
# `bin/safe-ruby script/validate_models_docs_content.rb --verbose #add debug printouts`

require_relative "../config/environment"

# Models in this list has support for system prompt according to the old static docs. But the model.schema.capabilities==false
# Todo: investigate if old docs are wrong or capabilities are wrong
SUPPORTS_SYSTEM_PROMPT_ISSUES = {
  "Llama-3-2-11B-Vision-Instruct": "You are a helpful assistant.",
  "Llama-3-2-90B-Vision-Instruct": "You are a helpful assistant.",
  "Llama-3-3-70B-Instruct": "You are a helpful assistant.",
  "Meta-Llama-3-8B-Instruct": "You are a helpful assistant.",
  "Meta-Llama-3-70B-Instruct": "You are a helpful assistant.",
  "jais-30b-chat": "You are a helpful assistant.",
  "Phi-3-small-8k-instruct": "You are a helpful assistant.", # Only Java wrong in static files
  "Phi-3-small-128k-instruct": "You are a helpful assistant.", # Only Java wrong in static files
  "Phi-3-medium-4k-instruct": "You are a helpful assistant.", # Only Java wrong in static files
  "Phi-3-medium-128k-instruct": "You are a helpful assistant.", # Only Java wrong in static files
  "Phi-4": "You are a helpful assistant.", # Only Java wrong in static files
  "Phi-4-multimodal-instruct": "You are a helpful assistant.",
  "Phi-4-mini-instruct": "You are a helpful assistant.",
  "DeepSeek-R1": "You are a helpful assistant.", # Only Java wrong in static files
}

EMBEDDING_FORMAT_ISSUE = [
  "This sample demonstrates a call to embeddings API",
  "The call is synchronous"
]

def validate(verbose:)
  all_models = GitHubModels::CatalogItem.all
  if all_models.count == 0
    puts "No models in db. Run `script/setup-models` first"
  end

  puts "Found #{all_models.count} models. Starting validation of Getting Started Content."
  correct_model_docs = 0
  incorrect_model_docs = 0
  all_models.each do |model|
    if validate_model(model, verbose)
      correct_model_docs += 1
    else
      incorrect_model_docs += 1
    end
  end

  puts "Finished validation of Getting Started Content."
  puts "Correct model docs: #{correct_model_docs}, incorrect model docs: #{incorrect_model_docs}"
end

def normalize_indentation(content)
  lines = content.split("\n")
  lines.map { |line| line.lstrip }.join("\n")
end

def remove_html_comments(content)
  previous = T.let(nil, T.untyped)
  while content != previous
    previous = content
    content = content.gsub(/<!--.*?-->/m, "")
  end
  content
end

def render_content(model, schema)
  GitHubModels::DocumentationController.new.render_getting_started_content(model, schema).deep_symbolize_keys
end

def validate_model(model, verbose)
  model_valid = T.let(true, T::Boolean)
  puts "Validating model: #{model.name}" if verbose

  data = GitHubModels::GettingStartedContent.build_template_data(model.to_model, model.to_schema)
  content = render_content(model.to_model, model.to_schema)

  model_id = "azureml://registries/#{model.to_model[:registry]}/models/#{model.to_model[:original_name]}"
  old_content = GitHubModels::Payloads::GettingStartedContent.fetch(model_id.to_sym)
  return unless old_content

  old_content.each do |language, language_entry|
    language_entry[:sdks].each do |sdk, sdk_entry|
      old_content_entry = sdk_entry[:content]

      normalized_sdk = sdk.to_s.strip
      if normalized_sdk == "azure-ai-inference" || normalized_sdk == "Azure.AI.Inference"
        normalized_sdk = "azure"
      elsif normalized_sdk == "mistralai"
        normalized_sdk = "mistral"
      elsif normalized_sdk == "cohereai"
        normalized_sdk = "cohere"
      end
      new_content_entry = content[language][:sdks][normalized_sdk.to_sym][:content]

      # Cleanup and ignore the number of new lines
      old_content_entry = old_content_entry.gsub(/[\r\n]+/, "\n").gsub(/^\s*$\n/, "").strip
      new_content_entry = new_content_entry.gsub(/[\r\n]+/, "\n").gsub(/^\s*$\n/, "").strip

      # Cut old_content_entry from '## 4' onwards
      if sdk.to_s == "curl"
        # Rest/curl do not have a install dependencies section so less chapters
        old_content_entry = "#{old_content_entry.split("## 3").first}"
        new_content_entry = new_content_entry.split("## 3").first
      else
        old_content_entry = "#{old_content_entry.split("## 4").first}"
        new_content_entry = new_content_entry.split("## 4").first
      end

      old_content_entry = normalize_indentation(old_content_entry)
      new_content_entry = normalize_indentation(new_content_entry)

      new_content_entry = remove_html_comments(new_content_entry)

      diff_output = diff(old_content_entry, new_content_entry)
      if diff_output != ""
        if SUPPORTS_SYSTEM_PROMPT_ISSUES.key?(model.name.to_sym) && diff_output.include?(SUPPORTS_SYSTEM_PROMPT_ISSUES[model.name.to_sym])
          puts "\tContent does not match:: Ignoring error due to model not support system_prompt but static docs has it for model: #{model.name}" if verbose
          puts "\tmodel capabilities #{data[:model_capabilities]}" if verbose
        elsif EMBEDDING_FORMAT_ISSUE.any? { |issue| diff_output.include?(issue) }
          puts "\tContent does not match:: Ignoring error due to embedding format" if verbose
          puts "---------------" if verbose
        else
          model_valid = false
          puts "\e[31mContent does not match:\e[0m model_name=#{model.name}, language=#{language}, sdk=#{sdk}"
          puts diff_output
          puts "\tmodel capabilities #{data[:model_capabilities]}"
          puts "---------------"
        end
      end
    end
  end
  model_valid
end

def diff(old_content_entry, new_content_entry)
  # Write content to temporary files
  old_file = Tempfile.new("old_content")
  new_file = Tempfile.new("new_content")
  old_file.write(old_content_entry)
  new_file.write(new_content_entry)
  old_file.close
  new_file.close

  # Use diff command to find differences
  diff_output = `diff -B -b #{old_file.path} #{new_file.path}`

  # Clean up temporary files
  old_file.unlink
  new_file.unlink
  diff_output
end

verbose = ARGV.include?("--verbose")
puts "verbose: #{verbose}"
validate(verbose: verbose)
