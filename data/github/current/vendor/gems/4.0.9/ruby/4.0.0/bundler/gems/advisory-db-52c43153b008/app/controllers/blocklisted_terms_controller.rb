# frozen_string_literal: true

class BlocklistedTermsController < InboxController
  def index; end

  def show
    blocklisted_term = BlocklistedTerm.find(params[:id])
    render locals: {
      blocklisted_term: blocklisted_term,
      blocklisted_reviews: blocklisted_term.advisory_reviews.paginate(page: params[:page]),
    }
  end

  def new
    render locals: { blocklisted_term: BlocklistedTerm.new }
  end

  def create
    blocklisted_term = BlocklistedTerm.new(blocklisted_term_params)

    if blocklisted_term.save
      ApplyBlocklistJob.set(queue: :high).perform_later(blocklisted_term_ids: [blocklisted_term.id])

      redirect_to blocklisted_term,
        notice: "Blocklisted term #{blocklisted_term.pattern} was created successfully! Looking for matches in existing advisory reviews..."
    else
      render action: :new, status: :unprocessable_entity, locals: {
        blocklisted_term: blocklisted_term,
      }
    end
  end

  def destroy
    blocklisted_term = BlocklistedTerm.find(params[:id])
    pattern = blocklisted_term.pattern
    advisory_review_ids = blocklisted_term.advisory_review_ids

    blocklisted_term.destroy!
    ApplyBlocklistJob.set(queue: :high).perform_later(advisory_review_ids: advisory_review_ids)

    redirect_to blocklisted_terms_path,
      notice: "Blocklisted term #{pattern} was deleted successfully!"
  end

  private

  def blocklisted_term_params
    params.require(:blocklisted_term).permit(:pattern, :level, :term_type)
  end
end
