require "simple_oauth"
require "open-uri"
require "json"

Plugin.create(:mikutter_aclog) do
  command(:mikutter_aclog_get_voters,
          name: "ふぁぼったユーザーを aclog から取得",
          condition: Plugin::Command[:CanReplyAll],
          visible: true,
          role: :timeline) do |m|
    m.messages.each do |msg|
      Thread.new {
        begin
          provider = "https://api.twitter.com/1.1/account/verify_credentials.json"
          oauth = { consumer_key: Service.primary.consumer_key,
                    consumer_secret: Service.primary.consumer_secret,
                    token: Service.primary.a_token,
                    token_secret: Service.primary.a_secret }
          h = SimpleOAuth::Header.new(:get, provider, {}, oauth)

          res = open("http://aclog.koba789.com/api/tweets/show.json?id=#{msg[:id]}",
                     "X-Auth-Service-Provider" => provider,
                     "X-Verify-Credentials-Authorization" => h.to_s)

          hash = JSON.parse(res.read).symbolize

          ((hash[:favoriters] || []).take(200) + (hash[:retweeters] || []).take(200)).uniq.each_slice(100) do |ids|
            Service.primary.user_lookup(user_id: ids.join(",")).next {|res|
              looked_up_users = {}
              res.each { |re|
                looked_up_users[re.id] = re }
              
              Gdk::MiraclePainter.findbymessage_d(msg).next { |mps|
                mps.deach { |mp|
                  favorite_subpart = mp.subparts.find { |sp| sp.class == Gdk::SubPartsFavorite } 
                  hash[:favoriters].each do |user_id|
                    user = looked_up_users[user_id]
                    if user
                      favorite_subpart.add(user) end end

                  retweet_subpart = mp.subparts.find { |sp| sp.class == Gdk::SubPartsRetweet }
                  hash[:retweeters].each do |user_id|
                    user = looked_up_users[user_id]
                    if user
                      retweet_subpart.add(user) end end
                  mp.on_modify
                } } } end
        rescue StandardError, Timeout::TimeoutError
          warn $!
          warn $@
        end } end end
end
