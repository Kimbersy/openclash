#!/usr/bin/env ruby
# frozen_string_literal: true
# One bounded HTTPS GET against an ALREADY RUNNING isolated loopback proxy.
# No browser, credentials, cookie jar, uploads, selector PUT, second core,
# subscription fetch, daemon, cron, config change or production install.
# This is a cheap PRECHECK only: NEVER grants BUSINESS_VERIFIED.
require 'open3'
require 'tempfile'
require 'uri'

module NotebookCtaLite
  CTA = 'https://notebook.google.com/?icid=home_maincta'
  APP = %w[notebook.google.com notebooklm.google.com].freeze
  LANDING = %w[notebook.google notebooklm.google].freeze
  LOGIN = %w[accounts.google.com].freeze

  def self.classify(curl_rc:, http_code:, headers:, effective:)
    return 'LIGHT_UNKNOWN_INCOMPLETE_HTTP' unless curl_rc == 0
    return 'LIGHT_UNKNOWN_HTTP_ERROR' unless http_code.to_s.match?(/\A[1-5]\d\d\z/)
    return 'LIGHT_UNKNOWN_HTTP_ERROR' if [403, 429, 451].include?(http_code.to_i)

    links = headers.to_s.lines.grep(/\Alocation\s*:/i)
                    .map { |line| line.sub(/\Alocation\s*:\s*/i, '').strip }
    links << effective.to_s
    links.each do |url|
      begin
        uri = URI.parse(url)
        # Accept known, absolute HTTPS destination only; do not infer from
        # attacker-supplied URLs, relative paths or arbitrary domains.
        next unless uri.is_a?(URI::HTTPS) && (APP + LANDING).include?(uri.host&.downcase)
        values = URI.decode_www_form(uri.query.to_s)
        return 'LIGHT_UNSUPPORTED_OBSERVED' if values.any? { |k, v| k == 'location' && v.downcase == 'unsupported' }
      rescue URI::InvalidURIError, ArgumentError
        next
      end
    end

    begin
      uri = URI.parse(effective.to_s)
      return 'LIGHT_UNKNOWN_UNREVIEWED_URL' unless uri.is_a?(URI::HTTPS)
      host = uri.host&.downcase
      # User-observed CTA behavior: a genuinely unsupported exit takes the
      # location=unsupported branch BEFORE the Google login path. A login
      # redirect on a dedicated isolated-node CTA GET is thus a useful
      # POSITIVE FIRST-STAGE signal, pending a real positive/negative pair
      # calibration. It does NOT attest the signed-in Notebook workspace.
      return 'LIGHT_LOGIN_PATH_CANDIDATE_UNVERIFIED' if LOGIN.include?(host)
      return 'LIGHT_MARKETING_ONLY' if LANDING.include?(host)
      return 'LIGHT_APP_HTTP_CANDIDATE_UNVERIFIED' if APP.include?(host) && http_code.to_i == 200
    rescue URI::InvalidURIError, ArgumentError
      return 'LIGHT_UNKNOWN_UNREVIEWED_URL'
    end
    'LIGHT_UNKNOWN_UNREVIEWED_REDIRECT'
  end

  def self.run_isolated(port)
    # A port for an already isolated, pre-existing test entrypoint. Avoid
    # modifying the existing OpenClash AI group just to reach a node.
    return 'LIGHT_HOLD_INVALID_PORT' unless (1024..65_535).cover?(port)
    Tempfile.create(['ai-notebook-lite-', '.headers']) do |file|
      file.chmod(0o600)
      args = [
        'curl', '-4', '-sS', '-L', '--proto', '=https',
        '--proto-redir', '=https', '--max-redirs', '4',
        '--connect-timeout', '4', '--max-time', '12',
        '--max-filesize', '393216',
        '--noproxy', '', '--proxy', "http://127.0.0.1:#{port}",
        '--dump-header', file.path,
        '--output', '/dev/null',
        '--write-out', '%{http_code} %{url_effective}',
        CTA
      ]
      stdout, _stderr, stat = Open3.capture3(*args)
      code, effective = stdout.split(' ', 2)
      classify(
        curl_rc: stat.exitstatus,
        http_code: code,
        headers: File.binread(file.path, 128_000),
        effective: effective.to_s.strip
      )
    end
  rescue Errno::ENOENT, Errno::EACCES, IOError, SystemCallError
    'LIGHT_UNKNOWN_RUNTIME_UNAVAILABLE'
  end
end

if $PROGRAM_NAME == __FILE__
  port_arg = ARGV.length == 1 && ARGV[0].match(/\A--isolated-port=(\d{4,5})\z/)
  if port_arg
    puts "NOTEBOOK_CTA=#{NotebookCtaLite.run_isolated(port_arg[1].to_i)} BUSINESS=UNKNOWN LIVE_WRITES=NONE"
  else
    warn 'Use only with an already-running, isolated loopback HTTP proxy: --isolated-port=17881'
    exit 2
  end
end
