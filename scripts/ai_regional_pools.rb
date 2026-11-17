#!/usr/bin/env ruby
# frozen_string_literal: true
# Pure offline candidate grouping / selection. No API calls or production mutations.
require 'time'
module AiRegionalPools
  SERVICES = %w[chatgpt gemini notebooklm].freeze
  module_function

  def recent?(value, now, max_age)
    t = Time.iso8601(value.to_s).utc
    t <= now && (now - t) <= max_age
  rescue ArgumentError, TypeError
    false
  end

  def valid_health?(node, now, ttl, min_samples, min_success)
    h = node['health']
    return false unless h.is_a?(Hash) && h['fingerprint'] == node['fingerprint']
    return false unless recent?(h['tested_at'], now, ttl)
    return false unless h['samples'].is_a?(Integer) && h['samples'] >= min_samples
    return false unless h['success_rate'].is_a?(Numeric) && h['success_rate'].between?(min_success, 1.0)
    return false unless h['rtt_p95_ms'].is_a?(Numeric) && h['rtt_p95_ms'].positive? && h['rtt_p95_ms'].finite?
    true
  end

  def valid_service?(node, service, now, ttl)
    services = node['services']
    return false unless services.is_a?(Hash)
    x = services[service]
    x.is_a?(Hash) && x['status'] == 'usable' && x['fingerprint'] == node['fingerprint'] && recent?(x['tested_at'], now, ttl)
  end

  def quality_key(node)
    h=node.fetch('health')
    rate=h.fetch('success_rate')
    rtt=h.fetch('rtt_p95_ms')
    speed=h['throughput_mbps']
    multiplier=node['cost_multiplier']
    speed=0.0 unless speed.is_a?(Numeric) && speed.finite? && speed>=0
    multiplier=1.0 unless multiplier.is_a?(Numeric) && multiplier.finite? && multiplier.positive?
    [-rate, rtt, -speed, multiplier, node.fetch('name')]
  end

  def build(records, coverage_verified: false, now: Time.now.utc, ttl_seconds: 24*3600, min_samples: 5, min_success: 0.95)
    raise ArgumentError, 'all enabled source coverage unverified' unless coverage_verified
    raise ArgumentError, 'invalid inventory' unless records.is_a?(Array)
    names={}
    seen={}
    duplicate_fingerprint=0
    collisions={}
    records.each do |node|
      next unless node.is_a?(Hash) && node['name'].is_a?(String) && !node['name'].empty? && node['fingerprint'].is_a?(String) && !node['fingerprint'].empty?
      name=node['name']
      fp=node['fingerprint']
      collisions[name]=true if names.key?(name) && names[name]!=fp
      names[name]=fp
      if seen.key?(fp)
        duplicate_fingerprint+=1
      else
        seen[fp]=node
      end
    end
    eligible=seen.values.select do |node|
      geo=node['egress']
      cc=geo.is_a?(Hash) ? geo['country'] : nil
      geo.is_a?(Hash) && geo['fingerprint']==node['fingerprint'] && geo['verified']==true &&
        cc.is_a?(String) && cc.match?(/\A[A-Z]{2}\z/) && recent?(geo['tested_at'],now,ttl_seconds) &&
        !collisions[node['name']] && valid_health?(node,now,ttl_seconds,min_samples,min_success)
    end
    per_service=SERVICES.to_h do |service|
      by_region={}
      eligible.each do |node|
        next unless valid_service?(node,service,now,ttl_seconds)
        (by_region[node['egress']['country']] ||= []) << node
      end
      [service,by_region.transform_values{|ns| ns.sort_by{|n| quality_key(n)}.map{|n| n['name']}}.sort.to_h]
    end
    all_services={}
    eligible.each do |node|
      next unless SERVICES.all?{|service| valid_service?(node,service,now,ttl_seconds)}
      (all_services[node['egress']['country']] ||= []) << node
    end
    all_services=all_services.transform_values{|ns| ns.sort_by{|n| quality_key(n)}.map{|n|n['name']}}.sort.to_h
    { 'per_service'=>per_service, 'all_services'=>all_services,
      'summary'=>{'raw_entries'=>records.length, 'unique_fingerprints'=>seen.length,
                  'duplicate_fingerprints'=>duplicate_fingerprint, 'name_conflicts'=>collisions.length,
                  'basic_qualified'=>eligible.length} }
  end

  # Only evaluates a proposed switch within an already-selected candidate pool.
  def decide(current:, ordered_candidates:, mode:, healthy:, consecutive_node_failures:, error_class:, cooldown_until: nil, now: Time.now.utc, required_failures: 3)
    return {'decision'=>'HOLD_MANUAL'} unless mode=='AUTO'
    return {'decision'=>'HOLD_HEALTHY'} if healthy
    return {'decision'=>'HOLD_NON_NODE_FAILURE'} unless error_class=='node_network'
    return {'decision'=>'HOLD_SUSPECT'} unless consecutive_node_failures.is_a?(Integer) && consecutive_node_failures >= required_failures
    if cooldown_until
      begin
        return {'decision'=>'HOLD_COOLDOWN'} if now < Time.iso8601(cooldown_until)
      rescue ArgumentError, TypeError
        return {'decision'=>'HOLD_INVALID_COOLDOWN'}
      end
    end
    return {'decision'=>'NO_VERIFIED_BACKUP'} unless ordered_candidates.is_a?(Array)
    backup=ordered_candidates.find{|name| name != current}
    return {'decision'=>'NO_VERIFIED_BACKUP'} unless backup
    {'decision'=>'SWITCH','to'=>backup}
  end
end
