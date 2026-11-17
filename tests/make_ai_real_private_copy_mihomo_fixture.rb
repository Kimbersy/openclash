#!/usr/bin/env ruby
# frozen_string_literal: true
# CI-only synthetic original config -> actual private-overlay function -> YAML.
require 'psych'
require_relative '../scripts/ai_real_config_private_copy_native_gate'

input = {
  'mode' => 'rule', 'allow-lan' => false, 'log-level' => 'silent',
  'mixed-port' => 7890,
  'proxies' => [
    {'name'=>'TEST_0','type'=>'http','server'=>'192.0.2.1','port'=>8080},
    {'name'=>'TEST_1','type'=>'http','server'=>'192.0.2.2','port'=>8080}
  ],
  'proxy-groups' => [
    {'name'=>'🤖 AI','type'=>'select','proxies'=>['TEST_0','DIRECT']},
    {'name'=>'🏰 Disney+','type'=>'select','proxies'=>['DIRECT']}
  ],
  'rules' => [
    'DOMAIN-SUFFIX,chatgpt.com,🤖 AI',
    'DOMAIN-SUFFIX,disneyplus.com,🏰 Disney+',
    'MATCH,DIRECT'
  ]
}
candidate, verdict = AiNotebookPrivateCopy.overlay(input)
abort('HOLD_OFFLINE_OVERLAY') unless verdict == 'PRIVATE_COPY_CANDIDATE'
abort('HOLD_MUTATION') unless candidate['proxy-groups'][0...-1] == input['proxy-groups'] &&
                               candidate['rules'] == input['rules'] &&
                               candidate['proxies'] == input['proxies']
path = ARGV.fetch(0)
File.write(path, Psych.dump(candidate))
puts 'SYNTHETIC_PRIVATE_CONFIG=PASS PRODUCTION_WRITES=NONE'
