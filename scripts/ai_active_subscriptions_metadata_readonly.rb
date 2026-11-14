#!/usr/bin/env ruby
# frozen_string_literal: true
# Only classifies UCI subscription SOURCE METADATA and update schedule.
# Absolutely no update, read remote URL, download, controller HTTP, or writes.
# Names, addresses, credentials and raw UCI text NEVER printed.
module AiActiveSubscriptionsMetadataReadOnly
  module_function
  MAX_UCI_BYTES = 2_000_000
  MAX_SUBSCRIPTION_SECTIONS = 200
  SECTION_ID = /[A-Za-z0-9_@\[\]-]+/
  FIELDS = %w[auto_update config_auto_update_mode config_update_week_time config_update_interval config_path].freeze

  def flag_class(values)
    return 'UNKNOWN' if values.nil? || values.empty?
    return 'CONFLICT' unless values.uniq.size == 1
    return 'ENABLED' if values.first == '1'
    return 'DISABLED' if values.first == '0'
    'UNKNOWN'
  end

  def parse_uci(text)
    return [nil,'HOLD_UCI_SIZE'] unless text.is_a?(String) &&
      text.bytesize.between?(1,MAX_UCI_BYTES)
    sections = {}
    options = Hash.new { |h,k| h[k]=[] }
    orphan = 0
    text.each_line do |raw|
      line = raw.strip
      if (m = /\Aopenclash\.([A-Za-z0-9_@\[\]-]+)=config_subscribe\z/.match(line))
        return [nil,'HOLD_SOURCE_SECTION_LIMIT'] if sections.length >= MAX_SUBSCRIPTION_SECTIONS
        return [nil,'HOLD_DUPLICATE_SOURCE_SECTION'] if sections.key?(m[1])
        sections[m[1]] = true
      elsif (m = /\Aopenclash\.([A-Za-z0-9_@\[\]-]+)\.(enabled|enable|address)=(.*)\z/.match(line))
        # Store only an *exact* 0/1 state or abstract address presence.
        # Never retain or echo source addresses, aliases, secrets or options.
        section, key, value = m.captures
        if key == 'address'
          present = value == "''" || value.empty? ? 'EMPTY' : 'SET'
          options[[section,'address']] << present
        else
          stripped = value.sub(/\A'/,'').sub(/'\z/,'')
          options[[section,key]] << (stripped.match?(/\A[01]\z/) ? stripped : 'UNKNOWN')
        end
      elsif (m = /\Aopenclash\.config\.(auto_update|config_auto_update_mode|config_update_week_time|config_update_interval|config_path)=(.*)\z/.match(line))
        key,value = m.captures
        stripped = value.sub(/\A'/,'').sub(/'\z/,'')
        val = if key == 'config_path'
          stripped.empty? ? 'EMPTY' : 'SET'
        elsif stripped.match?(/\A[0-9*]{1,8}\z/)
          stripped
        else
          'UNKNOWN'
        end
        options[['config',key]] << val
      end
    end
    known = 0
    disabled = 0
    unknown = 0
    conflict = 0
    address_missing = 0
    sections.each_key do |sid|
      status = flag_class(options[[sid,'enabled']] + options[[sid,'enable']])
      case status
      when 'ENABLED'
        known += 1
        addr = options[[sid,'address']]
        address_missing += 1 unless addr.length == 1 && addr[0]=='SET'
      when 'DISABLED' then disabled += 1
      when 'CONFLICT' then conflict += 1
      else unknown += 1
      end
    end
    orphan = options.keys.count{|sid,_| sid!='config' && !sections.key?(sid)}
    update = flag_class(options[['config','auto_update']])
    mode = options[['config','config_auto_update_mode']]
    schedule = if update=='ENABLED' && mode.length==1
      if mode.first=='0'
        w=options[['config','config_update_week_time']]
        w.length==1 ? (w.first=='*' ? 'DAILY' : w.first.match?(/\A[0-6]\z/) ? 'WEEKLY' : 'UNKNOWN') : 'UNKNOWN'
      elsif mode.first=='1'
        interval=options[['config','config_update_interval']]
        interval.length==1 && interval.first.match?(/\A[1-9][0-9]*\z/) &&
          interval.first.to_i.between?(1,10080) ? 'PERIODIC' : 'UNKNOWN'
      else 'UNKNOWN'
      end
    else 'UNKNOWN'
    end
    metrics = {
      'UCI_SUBSCRIPTION_SECTION_COUNT'=>sections.length,
      'UCI_EXPLICIT_ENABLED_COUNT'=>known,
      'UCI_EXPLICIT_DISABLED_COUNT'=>disabled,
      'UCI_ENABLE_FLAG_UNKNOWN_COUNT'=>unknown,
      'UCI_ENABLE_FLAG_CONFLICT_COUNT'=>conflict,
      'UCI_ENABLED_ADDRESS_MISSING_COUNT'=>address_missing,
      'UCI_ORPHAN_OPTION_BUCKETS'=>orphan,
      'UCI_SELECTED_CONFIG_DECLARED'=>options[['config','config_path']]==['SET'] ? 'YES' : 'NO',
      'UCI_AUTO_UPDATE'=>update,
      'UCI_UPDATE_CADENCE'=>schedule
    }
    result = if sections.empty?
      'HOLD_NO_CONFIG_SUBSCRIBE_SECTIONS'
    elsif conflict>0 || unknown>0 || orphan>0
      'HOLD_UCI_SUBSCRIPTION_STATUS_AMBIGUOUS'
    elsif known==0 || address_missing>0
      'HOLD_NO_CONFIRMED_ENABLED_SOURCE'
    else
      'UCI_ENABLED_SOURCE_METADATA_CLASSIFIED'
    end
    [metrics,result]
  end

  def uci_read
    body = ''
    IO.popen(['uci','-q','show','openclash'],err: File::NULL) do |io|
      body = io.read(MAX_UCI_BYTES+1)
      # Limit output silently; the UCI subprocess is local and read-only.
    end
    return nil unless $?.success? && body.bytesize.between?(1,MAX_UCI_BYTES)
    body
  rescue StandardError
    nil
  end

  def run
    puts 'SUBSCRIPTION_METADATA=START UCI_READ_ONLY=YES HTTP=NOT_REQUESTED'
    contents = uci_read
    unless contents
      puts 'SUBSCRIPTION_METADATA_RESULT=HOLD_UCI_READ_UNAVAILABLE'
      return
    end
    metrics,status = parse_uci(contents)
    puts "SUBSCRIPTION_METADATA_RESULT=#{status}"
    metrics&.each{|key,value| puts "#{key}=#{value}"}
    puts 'SUBSCRIPTION_NAMES_URLS_AND_SECRETS=NOT_EMITTED'
    puts 'ENABLED_SUBSCRIPTION_MERGE_PROVENANCE=NOT_VERIFIED'
    puts 'REMOTE_SUBSCRIPTION_REFRESH_SUCCESS=NOT_VERIFIED'
    puts 'MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED AI_BUSINESS=UNKNOWN'
  rescue StandardError
    puts 'SUBSCRIPTION_METADATA_RESULT=HOLD_RUNTIME'
  ensure
    puts 'PRODUCTION_CONFIG=UNCHANGED PROVIDER_REFRESH=NOT_RUN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  end
end

AiActiveSubscriptionsMetadataReadOnly.run if __FILE__ == $PROGRAM_NAME
