# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::DuplicationIdentifiers
  class CosineSimilarity < Base
    SIMILARITY_THRESHOLD = 0.8 # Anything below this is not considered a duplicate.
    MAX_STRING_LENGTH = 512 # Uniform length when comparing all comment body strings.

    # Maximum line number difference to consider comments as duplicates.
    # This is used to support blob_positions for file changes as well as new files.
    LINE_NUMBER_THRESHOLD = 1

    private

    sig { override.returns(T.untyped) }
    def duplicates
      vectorized_response_comments = vectorize_comments!(comments: response_comments)
      vectorized_existing_comments = vectorize_comments!(comments: existing_comments)

      vectorized_response_comments.flat_map do |path, comments_by_position|
        next unless existing_comments.key?(path)

        response_comments_for_path = comments_by_position.values.flatten
        existing_comments_for_path = T.must(vectorized_existing_comments[path]).values.flatten

        response_comments_for_path.flat_map do |response_comment|
          existing_comments_for_path.flat_map do |existing_comment|
            next unless within_allowed_line_number_difference?(response_comment:, existing_comment:)

            score = cosine_similarity(
              first_vector: response_comment[:vector],
              second_vector: existing_comment[:vector],
            )

            if T.must(score) >= SIMILARITY_THRESHOLD
              build_duplicate_hash(response_comment:, existing_comment:, score: T.must(score))
            end
          end
        end
      end
    end

    sig { params(response_comment: T.untyped, existing_comment: T.untyped).returns(T::Boolean) }
    def within_allowed_line_number_difference?(response_comment:, existing_comment:)
      line_number_difference = response_comment[:position].to_i - existing_comment[:position].to_i

      line_number_difference.abs <= LINE_NUMBER_THRESHOLD
    end

    sig { params(comments: T.untyped).returns(T.untyped) }
    def vectorize_comments!(comments:)
      comments.each_with_object({}) do |(path, comments_by_position), vectorized|
        vectorized[path] ||= {}

        comments_by_position.each do |position, comment_details|
          vectorized[path][position] ||= []

          comment_details.each do |comment_detail|
            vectorized[path][position] << comment_detail.merge(
              vector: vectorize(position:, body: comment_detail[:body]),
              position: position.to_i,
            )
          end
        end
      end
    end

    sig { params(position: T.any(String, Integer), body: String).returns(T::Array[T.any(Integer, Float)]) }
    def vectorize(position:, body:)
      # Normalize `position` into a vector
      position_vector = [position.to_f / 100_000]

      # Vectorize `body` using a simple hashing approach
      body_vector = body.bytes.map { |b| b / 255.0 }

      if body_vector.size < MAX_STRING_LENGTH
        body_vector = body_vector + [0] * (MAX_STRING_LENGTH - body_vector.size)
      else
        body_vector = body_vector[0...MAX_STRING_LENGTH]
      end

      position_vector + T.must(body_vector)
    end

    sig do
      params(
        first_vector: T::Array[T.any(Integer, Float)],
        second_vector: T::Array[T.any(Integer, Float)],
      ).returns(T.nilable(T.any(Integer, Float)))
    end
    def cosine_similarity(first_vector:, second_vector:)
      dot_product = first_vector.zip(second_vector).map { |a, b| T.must(a) * T.must(b) }.sum.to_f
      first_magnitude = Math.sqrt(first_vector.map { |x| x**2 }.sum.to_f)
      second_magnitude = Math.sqrt(second_vector.map { |x| x**2 }.sum.to_f)

      return 0 if first_magnitude.zero? || second_magnitude.zero?
      dot_product / (first_magnitude * second_magnitude)
    end
  end
end
