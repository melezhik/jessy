require 'rest_client'

class JCC < Struct.new( :host )

    def request http_method, uri, params = {}
        begin
            resp = RestClient.send(http_method, "#{host}#{uri}", params)
        rescue RestClient::Exception => e
            raise "unsuccessfull return from <#{http_method}> to <#{host}#{uri}> with params:#{params} :  <#{e.response.code}>\n\n<#{e.response}>"
        rescue => e
            raise "unsuccessfull return from <#{http_method}> to <#{host}#{uri}> with params:#{params} : <#{e.message}>"
        end
        resp
    end
end


