import type {EvaluatorCfg} from '../../config'
import {CoherenceEvaluator} from './coherence'
import {FluencyEvaluator} from './fluency'
import {GroundednessEvaluator} from './groundedness'
import {RelevanceEvaluator} from './relevance'
import {SimilarityEvaluator} from './similarity'

export const BuiltIn: Record<string, EvaluatorCfg> = {
  coherence: CoherenceEvaluator,
  fluency: FluencyEvaluator,
  similarity: SimilarityEvaluator,
  relevance: RelevanceEvaluator,
  groundedness: GroundednessEvaluator,
}
