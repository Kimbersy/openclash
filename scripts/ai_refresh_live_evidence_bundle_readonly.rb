#!/usr/bin/env ruby
# frozen_string_literal: true
# One-shot, read-only device handoff: update event/process-start heuristic +
# strictly PID-owned GET /proxies catalog. NO writes, reloads, selections.
# The two observations are NOT an authenticated complete reload attestation.
require_relative 'ai_refresh_activation_gate_readonly'
require_relative 'ai_live_membership_readonly'

module AiRefreshLiveEvidenceBundle
  module_function

  def run
    puts 'EVIDENCE_BUNDLE=START READ_ONLY=YES'
    a = AiRefreshActivationGate.run
    b = AiLiveMembership.run
    puts "EVIDENCE_BUNDLE=COMPLETE ACTIVATION_PROBE=#{a.zero? ? 'OBSERVED' : 'UNAVAILABLE'} LIVE_API_PROBE=#{b.zero? ? 'OBSERVED_OR_SAFE_HOLD' : 'UNAVAILABLE'}"
    puts 'AI_CATALOG_RECONCILE=NOT_AUTHORIZED'
    puts 'AI_NODE_SWITCH=NOT_AUTHORIZED'
    0
  rescue StandardError
    puts 'EVIDENCE_BUNDLE=SAFE_STOP_NO_PRIVATE_OUTPUT'
    2
  end
end

exit AiRefreshLiveEvidenceBundle.run if __FILE__ == $PROGRAM_NAME
