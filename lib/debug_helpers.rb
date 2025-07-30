# frozen_string_literal: true

# 開発環境でのデバッグ支援ヘルパー
module DebugHelpers

  # 条件付きデバッグ
  def debug_if(condition, message = nil)
    return unless Rails.env.development? && condition

    puts "🐛 Debug: #{message}" if message
    debugger
  end

  # ユーザー固有のデバッグ
  def debug_for_user(user_email, message = nil)
    return unless Rails.env.development?
    return unless current_user&.email == user_email

    puts "🐛 Debug for #{user_email}: #{message}" if message
    debugger
  end

  # パフォーマンス測定付きデバッグ
  def debug_with_timing(label = 'Operation')
    return yield unless Rails.env.development?

    start_time = Time.current
    result = yield
    end_time = Time.current

    puts "⏱️  #{label}: #{((end_time - start_time) * 1000).round(2)}ms"
    debugger if (end_time - start_time) > 1.0 # 1秒以上かかった場合

    result
  end

  # SQL クエリのデバッグ
  def debug_queries
    return yield unless Rails.env.development?

    queries = []
    subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      queries << {
        sql: event.payload[:sql],
        duration: event.duration.round(2),
      }
    end

    result = yield

    puts "📊 Executed #{queries.count} queries:"
    queries.each_with_index do |query, index|
      puts "  #{index + 1}. [#{query[:duration]}ms] #{query[:sql]}"
    end

    debugger if queries.count > 10 # N+1の可能性

    result
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

end

# ApplicationControllerに追加
class ApplicationController < ActionController::Base

  include DebugHelpers if Rails.env.development?

end

# ApplicationRecordに追加
class ApplicationRecord < ActiveRecord::Base

  extend DebugHelpers if Rails.env.development?

end
