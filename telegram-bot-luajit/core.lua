--[[

       _       _                                      _           _          _
      | |     | |                                    | |         | |        | |
      | |_ ___| | ___  __ _ _ __ __ _ _ __ ___ ______| |__   ___ | |_ ______| |_   _  __ _
      | __/ _ \ |/ _ \/ _` | '__/ _` | '_ ` _ \______| '_ \ / _ \| __|______| | | | |/ _` |
      | ||  __/ |  __/ (_| | | | (_| | | | | | |     | |_) | (_) | |_       | | |_| | (_| |
       \__\___|_|\___|\__, |_|  \__,_|_| |_| |_|     |_.__/ \___/ \__|      |_|\__,_|\__,_|jit
                       __/ |
                      |___/

      Version 1.10-0
      Copyright (c) 2020 Matthew Hesketh
      Copyright (c) 2021 Chris
      See LICENSE for details

]]

local api = {}
local https = require('ssl.https')
local multipart = require('multipart-post')
local ltn12 = require('ltn12')
local json = require('dkjson')
local html = require('htmlEntities')
local config = require('telegram-bot-luajit.config')

function api.configure(token, debug, endpoint)
    if not token or type(token) ~= 'string' then
        token = nil
    end
    if endpoint and type(endpoint) == 'string' then
        config['endpoint'] = endpoint
    end
    api.debug = debug and true or false
    api.token = assert(token, 'Please specify your bot API token you received from @BotFather!')
    repeat
        api.info = api.get_me()
    until api.info.result
    api.info = api.info.result
    api.info.name = api.info.first_name
    return api
end

function api.request(endpoint, parameters, file)
    assert(endpoint, 'You must specify an endpoint to make this request to!')
    parameters = parameters or {}
    for k, v in pairs(parameters) do
        parameters[k] = tostring(v)
    end
    if api.debug then
        local output = json.encode(parameters, { ['indent'] = true })
        print(output)
    end
    if file and next(file) ~= nil then
        local file_type, file_name = next(file)
        local file_res = io.open(file_name, 'r')
        if file_res then
            parameters[file_type] = {
                filename = file_name,
                data = file_res:read('*a')
            }
            file_res:close()
        else
            parameters[file_type] = file_name
        end
    end
    parameters = next(parameters) == nil and { '' } or parameters
    local response = {}
    local body, boundary = multipart.encode(parameters)
    local success, res = https.request(
        {
            ['url'] = endpoint,
            ['method'] = 'POST',
            ['headers'] = {
                ['Content-Type'] = 'multipart/form-data; boundary=' .. boundary,
                ['Content-Length'] = #body
            },
            ['source'] = ltn12.source.string(body),
            ['sink'] = ltn12.sink.table(response)
        }
    )
    if not success then
        print('Connection error [' .. res .. ']')
        return false, res
    end
    local jstr = table.concat(response)
    local jdat = json.decode(jstr)
    if not jdat then
        return false, res
    elseif not jdat.ok then
        local output = '\n' .. jdat.description .. ' [' .. jdat.error_code .. ']\n\nPayload: '
        output = output .. json.encode(parameters, { ['indent'] = true }) .. '\n'
        print(output)
        return false, jdat
    end
    return jdat, res
end

function api.get_me()
    local success, res = api.request(config.endpoint .. api.token .. '/getMe')
    return success, res
end

-------------
-- UPDATES --
-------------

function api.get_updates(timeout, offset, limit, allowed_updates) -- https://core.telegram.org/bots/api#getupdates
    assert(config.endpoint, 'You must specify an endpoint to make this request to!')
    allowed_updates = type(allowed_updates) == 'table' and json.encode(allowed_updates) or allowed_updates
    local success, res = api.request(
        string.format(
            '%s%s/getUpdates',
            config.endpoint,
            api.token
        ),
        {
            ['timeout'] = timeout,
            ['offset'] = offset,
            ['limit'] = limit,
            ['allowed_updates'] = allowed_updates
        }
    )
    return success, res
end

function api.set_webhook(url, certificate, max_connections, allowed_updates) -- https://core.telegram.org/bots/api#setwebhook
    allowed_updates = type(allowed_updates) == 'table' and json.encode(allowed_updates) or allowed_updates
    local success, res = api.request(config.endpoint .. api.token .. '/setWebhook',
        {
            ['url'] = url,
            ['max_connections'] = max_connections,
            ['allowed_updates'] = allowed_updates
        },
        { ['certificate'] = certificate }
    )
    return success, res
end

function api.delete_webhook() -- https://core.telegram.org/bots/api#deletewebhook
    local success, res = api.request(config.endpoint .. api.token .. '/deleteWebhook')
    return success, res
end

function api.get_webhook_info() -- https://core.telegram.org/bots/api#get_webhook_info
    local success, res = api.request(config.endpoint .. api.token .. '/getWebhookInfo')
    return success, res
end

-------------
-- METHODS --
-------------

function api.send_message(message, text, parse_mode, disable_web_page_preview, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#sendmessage
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    message = (type(message) == 'table' and message.chat and message.chat.id) and message.chat.id or message
    parse_mode = (type(parse_mode) == 'boolean' and parse_mode == true) and 'markdown' or parse_mode
    if disable_web_page_preview == nil then
        disable_web_page_preview = true
    end
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendMessage',
        {
            ['chat_id'] = message,
            ['text'] = text,
            ['parse_mode'] = parse_mode,
            ['disable_web_page_preview'] = disable_web_page_preview,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        }
    )
    return success, res
end

function api.send_reply(message, text, parse_mode, disable_web_page_preview, reply_markup, disable_notification) -- A variant of api.send_message(), optimised for sending a message as a reply.
    if type(message) ~= 'table' or not message.chat or not message.chat.id or not message.message_id then
        return false
    end
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    parse_mode = (type(parse_mode) == 'boolean' and parse_mode == true) and 'markdown' or parse_mode
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendMessage',
        {
            ['chat_id'] = message.chat.id,
            ['text'] = text,
            ['parse_mode'] = parse_mode,
            ['disable_web_page_preview'] = disable_web_page_preview,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = message.message_id,
            ['reply_markup'] = reply_markup
        }
    )
    return success, res
end

function api.forward_message(chat_id, from_chat_id, disable_notification, message_id) -- https://core.telegram.org/bots/api#forwardmessage
    local success, res = api.request(
        config.endpoint .. api.token .. '/forwardMessage',
        {
            ['chat_id'] = chat_id,
            ['from_chat_id'] = from_chat_id,
            ['disable_notification'] = disable_notification,
            ['message_id'] = message_id
        }
    )
    return success, res
end

function api.send_photo(chat_id, photo, caption, parse_mode, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#sendphoto
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendPhoto',
        {
            ['chat_id'] = chat_id,
            ['caption'] = caption,
            ['parse_mode'] = parse_mode,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        },
        {
            ['photo'] = photo
        }
    )
    return success, res
end

function api.send_audio(chat_id, audio, caption, parse_mode, duration, performer, title, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#sendaudio
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendAudio',
        {
            ['chat_id'] = chat_id,
            ['caption'] = caption,
            ['parse_mode'] = parse_mode,
            ['duration'] = duration,
            ['performer'] = performer,
            ['title'] = title,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        },
        { ['audio'] = audio }
    )
    return success, res
end

function api.send_document(chat_id, document, caption, parse_mode, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#senddocument
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendDocument',
        {
            ['chat_id'] = chat_id,
            ['caption'] = caption,
            ['parse_mode'] = parse_mode,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        },
        { ['document'] = document }
    )
    return success, res
end

function api.send_video(chat_id, video, duration, width, height, caption, parse_mode, supports_streaming, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#sendvideo
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendVideo',
        {
            ['chat_id'] = chat_id,
            ['duration'] = duration,
            ['width'] = width,
            ['height'] = height,
            ['caption'] = caption,
            ['parse_mode'] = parse_mode,
            ['supports_streaming'] = supports_streaming,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        },
        { ['video'] = video }
    )
    return success, res
end

function api.send_animation(chat_id, animation, duration, width, height, thumb, caption, parse_mode, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#sendanimation
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendAnimation',
        {
            ['chat_id'] = chat_id,
            ['duration'] = duration,
            ['width'] = width,
            ['height'] = height,
            ['caption'] = caption,
            ['parse_mode'] = parse_mode,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        }, {
            ['animation'] = animation,
            ['thumb'] = thumb
        }
    )
    return success, res
end

function api.send_voice(chat_id, voice, caption, parse_mode, duration, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#sendvoice
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendVoice',
        {
            ['chat_id'] = chat_id,
            ['caption'] = caption,
            ['parse_mode'] = parse_mode,
            ['duration'] = duration,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        },
        { ['voice'] = voice }
    )
    return success, res
end

function api.send_video_note(chat_id, video_note, duration, length, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#sendvideonote
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendVideoNote',
        {
            ['chat_id'] = chat_id,
            ['duration'] = duration,
            ['length'] = length,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        },
        { ['video_note'] = video_note }
    )
    return success, res
end

function api.send_media_group(chat_id, media, disable_notification, reply_to_message_id) -- https://core.telegram.org/bots/api#sendmediagroup
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendMediaGroup',
        {
            ['chat_id'] = chat_id,
            ['media'] = media,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id
        }
    )
    return success, res
end

function api.send_location(chat_id, latitude, longitude, live_period, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#sendlocation
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendLocation',
        {
            ['chat_id'] = chat_id,
            ['latitude'] = latitude,
            ['longitude'] = longitude,
            ['live_period'] = live_period,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        }
    )
    return success, res
end

function api.edit_message_live_location(chat_id, message_id, inline_message_id, latitude, longitude, reply_markup) -- https://core.telegram.org/bots/api#editmessagelivelocation
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/editMessageLiveLocation',
        {
            ['chat_id'] = chat_id,
            ['message_id'] = message_id,
            ['inline_message_id'] = inline_message_id,
            ['latitude'] = latitude,
            ['longitude'] = longitude,
            ['reply_markup'] = reply_markup
        }
    )
    return success, res
end

function api.stop_message_live_location(chat_id, message_id, inline_message_id, reply_markup) -- https://core.telegram.org/bots/api#stopmessagelivelocation
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/stopMessageLiveLocation',
        {
            ['chat_id'] = chat_id,
            ['message_id'] = message_id,
            ['inline_message_id'] = inline_message_id,
            ['reply_markup'] = reply_markup
        }
    )
    return success, res
end

function api.send_venue(chat_id, latitude, longitude, title, address, foursquare_id, foursquare_type, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#sendvenue
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendVenue',
        {
            ['chat_id'] = chat_id,
            ['latitude'] = latitude,
            ['longitude'] = longitude,
            ['title'] = title,
            ['address'] = address,
            ['foursquare_id'] = foursquare_id,
            ['foursquare_type'] = foursquare_type,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        }
    )
    return success, res
end

function api.send_contact(chat_id, phone_number, first_name, last_name, vcard, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#sendcontact
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendContact',
        {
            ['chat_id'] = chat_id,
            ['phone_number'] = phone_number,
            ['first_name'] = first_name,
            ['last_name'] = last_name,
            ['vcard'] = vcard,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        }
    )
    return success, res
end

function api.send_poll(chat_id, question, options, is_anonymous, poll_type, allows_multiple_answers, correct_option_id, explanation, explanation_parse_mode, open_period, close_date, is_closed, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#sendpoll
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    is_anonymous = type(is_anonymous) == 'boolean' and is_anonymous or false
    allows_multiple_answers = type(allows_multiple_answers) == 'boolean' and allows_multiple_answers or false
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendPoll',
        {
            ['chat_id'] = chat_id,
            ['question'] = question,
            ['options'] = options,
            ['is_anonymous'] = is_anonymous,
            ['type'] = poll_type,
            ['allows_multiple_answers'] = allows_multiple_answers,
            ['correct_option_id'] = correct_option_id,
            ['explanation'] = explanation,
            ['explanation_parse_mode'] = explanation_parse_mode,
            ['open_period'] = open_period,
            ['close_date'] = close_date,
            ['is_closed'] = is_closed,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        }
    )
    return success, res
end

function api.send_dice(chat_id, emoji, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#senddice
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendDice',
        {
            ['chat_id'] = chat_id,
            ['emoji'] = emoji,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        }
    )
    return success, res
end

function api.send_chat_action(chat_id, action) -- https://core.telegram.org/bots/api#sendchataction
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendChatAction',
        {
            ['chat_id'] = chat_id,
            ['action'] = action or 'typing' -- Fallback to `typing` as the default action.
        }
    )
    return success, res
end

function api.get_user_profile_photos(user_id, offset, limit) -- https://core.telegram.org/bots/api#getuserprofilephotos
    local success, res = api.request(
        config.endpoint .. api.token .. '/getUserProfilePhotos',
        {
            ['user_id'] = user_id,
            ['offset'] = offset,
            ['limit'] = limit
        }
    )
    return success, res
end

function api.get_file(file_id) -- https://core.telegram.org/bots/api#getfile
    local success, res = api.request(
        config.endpoint .. api.token .. '/getFile',
        { ['file_id'] = file_id }
    )
    return success, res
end

function api.ban_chat_member(chat_id, user_id, until_date) -- https://core.telegram.org/bots/api#kickchatmember
    local success, res = api.request(
        config.endpoint .. api.token .. '/kickChatMember',
        {
            ['chat_id'] = chat_id,
            ['user_id'] = user_id,
            ['until_date'] = until_date
        }
    )
    return success, res
end

function api.kick_chat_member(chat_id, user_id)
    local success, res = api.request(
        config.endpoint .. api.token .. '/unbanChatMember',
        {
            ['chat_id'] = chat_id,
            ['user_id'] = user_id
        }
    )
    return success, res
end

function api.unban_chat_member(chat_id, user_id) -- https://core.telegram.org/bots/api#unbanchatmember
    local success, res
    for _ = 1, 3 do -- Repeat 3 times to ensure the user was unbanned (I've encountered issues before so
    -- this is for precautionary measures.)
        success, res = api.request(
            config.endpoint .. api.token .. '/unbanChatMember',
            {
                ['chat_id'] = chat_id,
                ['user_id'] = user_id
            }
        )
        if success then -- If one of the first 3 attempts is a success (which it typically will be), we can just stop the loop
            return success, res
        end
    end
    return success, res
end

function api.restrict_chat_member(chat_id, user_id, until_date, can_send_messages, can_send_media_messages, can_send_polls, can_send_other_messages, can_add_web_page_previews, can_change_info, can_invite_users, can_pin_messages) -- https://core.telegram.org/bots/api#restrictchatmember
    if until_date == ('forever' or 'permanently') then
        until_date = os.time() - 1000 -- indefinite restriction
    end
    local permissions = type(can_send_messages) == 'table' and can_send_messages or { -- allows the user to pass the permissions as a table should they want to do so
        ['can_send_messages'] = can_send_messages,
        ['can_send_media_messages'] = can_send_media_messages,
        ['can_send_polls'] = can_send_polls,
        ['can_send_other_messages'] = can_send_other_messages,
        ['can_add_web_page_previews'] = can_add_web_page_previews,
        ['can_change_info'] = can_change_info,
        ['can_invite_users'] = can_invite_users,
        ['can_pin_messages'] = can_pin_messages
    }
    local success, res = api.request(
        config.endpoint .. api.token .. '/restrictChatMember',
        {
            ['chat_id'] = chat_id,
            ['user_id'] = user_id,
            ['permissions'] = json.encode(permissions),
            ['until_date'] = until_date
        }
    )
    return success, res
end

function api.promote_chat_member(chat_id, user_id, can_change_info, can_post_messages, can_edit_messages, can_delete_messages, can_invite_users, can_restrict_members, can_pin_messages, can_promote_members) -- https://core.telegram.org/bots/api#promotechatmember
    local success, res = api.request(
        config.endpoint .. api.token .. '/promoteChatMember',
        {
            ['chat_id'] = chat_id,
            ['user_id'] = user_id,
            ['can_change_info'] = can_change_info,
            ['can_post_messages'] = can_post_messages,
            ['can_edit_messages'] = can_edit_messages,
            ['can_delete_messages'] = can_delete_messages,
            ['can_invite_users'] = can_invite_users,
            ['can_restrict_members'] = can_restrict_members,
            ['can_pin_messages'] = can_pin_messages,
            ['can_promote_members'] = can_promote_members
        }
    )
    return success, res
end

function api.set_chat_administrator_custom_title(chat_id, user_id, custom_title) -- https://core.telegram.org/bots/api#setchatadministratorcustomtitle
    if custom_title:len() > 16 then -- telegram doesn't allow custom titles longer than 16 chars
        custom_title = custom_title:sub(1, 16)
    end
    local success, res = api.request(
        config.endpoint .. api.token .. '/setChatAdministratorCustomTitle',
        {
            ['chat_id'] = chat_id,
            ['user_id'] = user_id,
            ['custom_title'] = custom_title
        }
    )
    return success, res
end

function api.set_chat_permissions(chat_id, can_send_messages, can_send_media_messages, can_send_polls, can_send_other_messages, can_add_web_page_previews, can_change_info, can_invite_users, can_pin_messages) -- https://core.telegram.org/bots/api#setchatpermissions
    local permissions = type(can_send_messages) == 'table' and can_send_messages or { -- allows the user to pass the permissions as a table should they want to do so
        ['can_send_messages'] = can_send_messages,
        ['can_send_media_messages'] = can_send_media_messages,
        ['can_send_polls'] = can_send_polls,
        ['can_send_other_messages'] = can_send_other_messages,
        ['can_add_web_page_previews'] = can_add_web_page_previews,
        ['can_change_info'] = can_change_info,
        ['can_invite_users'] = can_invite_users,
        ['can_pin_messages'] = can_pin_messages
    }
    local success, res = api.request(
        config.endpoint .. api.token .. '/setChatPermissions',
        {
            ['chat_id'] = chat_id,
            ['permissions'] = json.encode(permissions)
        }
    )
    return success, res
end

function api.export_chat_invite_link(chat_id) -- https://core.telegram.org/bots/api#exportchatinvitelink
    local success, res = api.request(
        config.endpoint .. api.token .. '/exportChatInviteLink',
        { ['chat_id'] = chat_id }
    )
    return success, res
end

function api.set_chat_photo(chat_id, photo) -- https://core.telegram.org/bots/api#setchatphoto
    local success, res = api.request(
        config.endpoint .. api.token .. '/setChatPhoto',
        { ['chat_id'] = chat_id },
        { ['photo'] = photo }
    )
    return success, res
end

function api.delete_chat_photo(chat_id) -- https://core.telegram.org/bots/api#deletechatphoto
    local success, res = api.request(
        config.endpoint .. api.token .. '/deleteChatPhoto',
        { ['chat_id'] = chat_id }
    )
    return success, res
end

function api.set_chat_title(chat_id, title) -- https://core.telegram.org/bots/api#setchattitle
    if title:len() > 255 then -- telegram won't allow chat titles greater than 255 chars
        title = title:sub(1, 255)
    end
    local success, res = api.request(
        config.endpoint .. api.token .. '/setChatTitle',
        {
            ['chat_id'] = chat_id,
            ['title'] = title
        }
    )
    return success, res
end

function api.set_chat_description(chat_id, description) -- https://core.telegram.org/bots/api#setchatdescription
    if description:len() > 255 then -- telegram won't allow chat descriptions greater than 255 chars
        description = description:sub(1, 255)
    end
    local success, res = api.request(
        config.endpoint .. api.token .. '/setChatDescription',
        {
            ['chat_id'] = chat_id,
            ['description'] = description
        }
    )
    return success, res
end

function api.pin_chat_message(chat_id, message_id, disable_notification) -- https://core.telegram.org/bots/api#pinchatmessage
    local success, res = api.request(
        config.endpoint .. api.token .. '/pinChatMessage',
        {
            ['chat_id'] = chat_id,
            ['message_id'] = message_id,
            ['disable_notification'] = disable_notification
        }
    )
    return success, res
end

function api.unpin_chat_message(chat_id) -- https://core.telegram.org/bots/api#unpinchatmessage
    local success, res = api.request(
        config.endpoint .. api.token .. '/unpinChatMessage',
        { ['chat_id'] = chat_id }
    )
    return success, res
end

function api.leave_chat(chat_id) -- https://core.telegram.org/bots/api#leavechat
    local success, res = api.request(
        config.endpoint .. api.token .. '/leaveChat',
        { ['chat_id'] = chat_id }
    )
    return success, res
end

function api.get_chat(chat_id) -- https://core.telegram.org/bots/api#getchat
    local success, result = api.request(
        config.endpoint .. api.token .. '/getChat',
        { ['chat_id'] = chat_id }
    )
    if not success or not success.result then
        return success, result
    end
    if success.result.username and success.result.type == 'private' then
        local old_timeout = https.TIMEOUT
        https.TIMEOUT = 1
        local scrape, scrape_res = https.request('https://t.me/' .. success.result.username)
        https.TIMEOUT = old_timeout
        if scrape_res ~= 200 then
            return success, result
        end
        local bio = scrape:match('%<div class="tgme_page_description "%>(.-)%</div%>')
        if not bio then
            return success
        end
        bio = bio:gsub('%b<>', '')
        bio = html.decode(bio)
        success.result.bio = bio
    end
    return success, result
end

function api.get_chat_administrators(chat_id) -- https://core.telegram.org/bots/api#getchatadministrators
    local success, res = api.request(
        config.endpoint .. api.token .. '/getChatAdministrators',
        { ['chat_id'] = chat_id }
    )
    return success, res
end

function api.get_chat_members_count(chat_id) -- https://core.telegram.org/bots/api#getchatmemberscount
    local success, res = api.request(
        config.endpoint .. api.token .. '/getChatMembersCount',
        { ['chat_id'] = chat_id }
    )
    return success, res
end

function api.get_chat_member(chat_id, user_id) -- https://core.telegram.org/bots/api#getchatmember
    local success, res = api.request(
        config.endpoint .. api.token .. '/getChatMember',
        {
            ['chat_id'] = chat_id,
            ['user_id'] = user_id
        }
    )
    return success, res
end

function api.set_chat_sticker_set(chat_id, sticker_set_name) -- https://core.telegram.org/bots/api#setchatstickerset
    local success, res = api.request(
        config.endpoint .. api.token .. '/setChatStickerSet',
        {
            ['chat_id'] = chat_id,
            ['sticker_set_name'] = sticker_set_name
        }
    )
    return success, res
end

function api.delete_chat_sticker_set(chat_id) -- https://core.telegram.org/bots/api#deletechatstickerset
    local success, res = api.request(
        config.endpoint .. api.token .. '/deleteChatStickerSet',
        { ['chat_id'] = chat_id }
    )
    return success, res
end

function api.answer_callback_query(callback_query_id, text, show_alert, url, cache_time) -- https://core.telegram.org/bots/api#answercallbackquery
    local success, res = api.request(
        config.endpoint .. api.token .. '/answerCallbackQuery',
        {
            ['callback_query_id'] = callback_query_id,
            ['text'] = text,
            ['show_alert'] = show_alert,
            ['url'] = url,
            ['cache_time'] = cache_time
        }
    )
    return success, res
end

function api.set_my_commands(commands) -- https://core.telegram.org/bots/api#setmycommands
    local success, res = api.request(
        config.endpoint .. api.token .. '/setMyCommands',
        { ['commands'] = commands }
    )
    return success, res
end

function api.get_my_commands() -- https://core.telegram.org/bots/api#getmycommands
    local success, res = api.request(config.endpoint .. api.token .. '/getMyCommands')
    return success, res
end

function api.edit_message_text(chat_id, message_id, text, parse_mode, disable_web_page_preview, reply_markup, inline_message_id) -- https://core.telegram.org/bots/api#editmessagetext
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    parse_mode = (type(parse_mode) == 'boolean' and parse_mode == true) and 'markdown' or parse_mode
    local success, res = api.request(
        config.endpoint .. api.token .. '/editMessageText',
        {
            ['chat_id'] = chat_id,
            ['message_id'] = message_id,
            ['inline_message_id'] = inline_message_id,
            ['text'] = text,
            ['parse_mode'] = parse_mode,
            ['disable_web_page_preview'] = disable_web_page_preview,
            ['reply_markup'] = reply_markup
        }
    )
    if not success then
        success, res = api.request(
            config.endpoint .. api.token .. '/editMessageText',
            {
                ['chat_id'] = chat_id,
                ['message_id'] = inline_message_id,
                ['inline_message_id'] = message_id,
                ['text'] = text,
                ['parse_mode'] = parse_mode,
                ['disable_web_page_preview'] = disable_web_page_preview,
                ['reply_markup'] = reply_markup
            }
        )
    end
    return success, res
end

function api.edit_message_caption(chat_id, message_id, caption, reply_markup, inline_message_id) -- https://core.telegram.org/bots/api#editmessagecaption
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/editMessageCaption',
        {
            ['chat_id'] = chat_id,
            ['message_id'] = message_id,
            ['inline_message_id'] = inline_message_id,
            ['caption'] = caption,
            ['reply_markup'] = reply_markup
        }
    )
    if not success then
        success, res = api.request(
            config.endpoint .. api.token .. '/editMessageCaption',
            {
                ['chat_id'] = chat_id,
                ['message_id'] = inline_message_id,
                ['inline_message_id'] = message_id,
                ['caption'] = caption,
                ['reply_markup'] = reply_markup
            }
        )
    end
    return success, res
end

function api.edit_message_media(chat_id, message_id, media, reply_markup, inline_message_id) -- https://core.telegram.org/bots/api#editmessagemedia
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    media = type(media) == 'table' and json.encode(media) or media
    local success, res = api.request(
        config.endpoint .. api.token .. '/editMessageMedia',
        {
            ['chat_id'] = chat_id,
            ['message_id'] = message_id,
            ['inline_message_id'] = inline_message_id,
            ['media'] = media,
            ['reply_markup'] = reply_markup
        }
    )
    if not success then
        success, res = api.request(
            config.endpoint .. api.token .. '/editMessageMedia',
            {
                ['chat_id'] = chat_id,
                ['message_id'] = inline_message_id,
                ['inline_message_id'] = message_id,
                ['media'] = media,
                ['reply_markup'] = reply_markup
            }
        )
    end
    return success, res
end

function api.edit_message_reply_markup(chat_id, message_id, inline_message_id, reply_markup) -- https://core.telegram.org/bots/api#editmessagereplymarkup
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/editMessageReplyMarkup',
        {
            ['chat_id'] = chat_id,
            ['message_id'] = message_id,
            ['inline_message_id'] = inline_message_id,
            ['reply_markup'] = reply_markup
        }
    )
    if not success then
        success, res = api.request(
            config.endpoint .. api.token .. '/editMessageReplyMarkup',
            {
                ['chat_id'] = chat_id,
                ['message_id'] = inline_message_id,
                ['inline_message_id'] = message_id,
                ['reply_markup'] = reply_markup
            }
        )
    end
    return success, res
end

function api.stop_poll(chat_id, message_id, reply_markup) -- https://core.telegram.org/bots/api#stoppoll
    local success, res = api.request(
        config.endpoint .. api.token .. '/stopPoll',
        {
            ['chat_id'] = chat_id,
            ['message_id'] = message_id,
            ['reply_markup'] = reply_markup
        }
    )
    return success, res
end

function api.delete_message(chat_id, message_id) -- https://core.telegram.org/bots/api#deletemessage
    local success, res = api.request(
        config.endpoint .. api.token .. '/deleteMessage',
        {
            ['chat_id'] = chat_id,
            ['message_id'] = message_id
        }
    )
    return success, res
end

--------------
-- STICKERS --
--------------

function api.send_sticker(chat_id, sticker, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#sendsticker
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendSticker',
        {
            ['chat_id'] = chat_id,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        },
        { ['sticker'] = sticker }
    )
    return success, res
end

function api.get_sticker_set(name) -- https://core.telegram.org/bots/api#getstickerset
    local success, res = api.request(
        config.endpoint .. api.token .. '/getStickerSet',
        { ['name'] = name }
    )
    return success, res
end

function api.upload_sticker_file(user_id, png_sticker) -- https://core.telegram.org/bots/api#uploadstickerfile
    local success, res = api.request(
        config.endpoint .. api.token .. '/uploadStickerFile',
        { ['user_id'] = user_id },
        { ['png_sticker'] = png_sticker }
    )
    return success, res
end

function api.create_new_sticker_set(user_id, name, title, png_sticker, emojis, contains_masks, mask_position) -- https://core.telegram.org/bots/api#createnewstickerset
    mask_position = type(mask_position) == 'table' and json.encode(mask_position) or mask_position
    local success, res = api.request(
        config.endpoint .. api.token .. '/createNewStickerSet',
        {
            ['user_id'] = user_id,
            ['name'] = name,
            ['title'] = title,
            ['emojis'] = emojis,
            ['contains_masks'] = contains_masks,
            ['mask_position'] = mask_position
        },
        { ['png_sticker'] = png_sticker }
    )
    return success, res
end

function api.add_sticker_to_set(user_id, name, png_sticker, emojis, mask_position) -- https://core.telegram.org/bots/api#addstickertoset
    mask_position = type(mask_position) == 'table' and json.encode(mask_position) or mask_position
    local success, res = api.request(
        config.endpoint .. api.token .. '/addStickerToSet',
        {
            ['user_id'] = user_id,
            ['name'] = name,
            ['emojis'] = emojis,
            ['mask_position'] = mask_position
        },
        { ['png_sticker'] = png_sticker }
    )
    return success, res
end

function api.set_sticker_position_in_set(sticker, position) -- https://core.telegram.org/bots/api#setstickerpositioninset
    local success, res = api.request(
        config.endpoint .. api.token .. '/setStickerPositionInSet',
        {
            ['sticker'] = sticker,
            ['position'] = position
        }
    )
    return success, res
end

function api.delete_sticker_from_set(sticker) -- https://core.telegram.org/bots/api#deletestickerfromset
    local success, res = api.request(
        config.endpoint .. api.token .. '/deleteStickerFromSet',
        { ['sticker'] = sticker }
    )
    return success, res
end

function api.set_sticker_set_thumb(name, user_id, thumb) -- https://core.telegram.org/bots/api#setstickersetthumb
    local success, res = api.request(
        config.endpoint .. api.token .. '/setStickerSetThumb',
        {
            ['name'] = name,
            ['user_id'] = user_id
        },
        { ['thumb'] = thumb }
    )
    return success, res
end

function api.answer_inline_query(inline_query_id, results, cache_time, is_personal, next_offset, switch_pm_text, switch_pm_parameter) -- https://core.telegram.org/bots/api#answerinlinequery
    if results and type(results) == 'table' then
        if results.id then
            results = { results }
        end
        results = json.encode(results)
    end
    local success, res = api.request(
        config.endpoint .. api.token .. '/answerInlineQuery',
        {
            ['inline_query_id'] = inline_query_id,
            ['results'] = results,
            ['switch_pm_text'] = switch_pm_text,
            ['switch_pm_parameter'] = switch_pm_parameter,
            ['cache_time'] = cache_time,
            ['is_personal'] = is_personal,
            ['next_offset'] = next_offset
        }
    )
    return success, res
end

--------------
-- PAYMENTS --
--------------

function api.send_invoice(chat_id, title, description, payload, provider_token, start_parameter, currency, prices, provider_data, photo_url, photo_size, photo_width, photo_height, need_name, need_phone_number, need_email, need_shipping_address, is_flexible, disable_notification, reply_to_message_id, reply_markup)
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendInvoice',
        {
            ['chat_id'] = chat_id,
            ['title'] = title,
            ['description'] = description,
            ['payload'] = payload,
            ['provider_token'] = provider_token,
            ['start_parameter'] = start_parameter,
            ['currency'] = currency,
            ['prices'] = prices,
            ['provider_data'] = provider_data,
            ['photo_url'] = photo_url,
            ['photo_size'] = photo_size,
            ['photo_width'] = photo_width,
            ['photo_height'] = photo_height,
            ['need_name'] = need_name,
            ['need_phone_number'] = need_phone_number,
            ['need_email'] = need_email,
            ['need_shipping_address'] = need_shipping_address,
            ['is_flexible'] = is_flexible,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        }
    )
    return success, res
end

function api.answer_shipping_query(shipping_query_id, ok, shipping_options, error_message)
    local success, res = api.request(
        config.endpoint .. api.token .. '/answerShippingQuery',
        {
            ['shipping_query_id'] = shipping_query_id,
            ['ok'] = ok,
            ['shipping_options'] = shipping_options,
            ['error_message'] = error_message
        }
    )
    return success, res
end

function api.answer_pre_checkout_query(pre_checkout_query_id, ok, error_message)
    local success, res = api.request(
        config.endpoint .. api.token .. '/answerPreCheckoutQuery',
        {
            ['pre_checkout_query_id'] = pre_checkout_query_id,
            ['ok'] = ok,
            ['error_message'] = error_message
        }
    )
    return success, res
end

-----------
-- GAMES --
-----------

function api.send_game(chat_id, game_short_name, disable_notification, reply_to_message_id, reply_markup) -- https://core.telegram.org/bots/api#sendgame
    reply_markup = type(reply_markup) == 'table' and json.encode(reply_markup) or reply_markup
    local success, res = api.request(
        config.endpoint .. api.token .. '/sendGame',
        {
            ['chat_id'] = chat_id,
            ['game_short_name'] = game_short_name,
            ['disable_notification'] = disable_notification,
            ['reply_to_message_id'] = reply_to_message_id,
            ['reply_markup'] = reply_markup
        }
    )
    return success, res
end

function api.set_game_score(chat_id, user_id, message_id, score, force, disable_edit_message, inline_message_id) -- https://core.telegram.org/bots/api#setgamescore
    local success, res = api.request(
        config.endpoint .. api.token .. '/setGameScore',
        {
            ['user_id'] = user_id,
            ['score'] = score,
            ['force'] = force,
            ['disable_edit_message'] = disable_edit_message,
            ['chat_id'] = chat_id,
            ['message_id'] = message_id,
            ['inline_message_id'] = inline_message_id
        }
    )
    return success, res
end

function api.get_game_high_scores(chat_id, user_id, message_id, inline_message_id) -- https://core.telegram.org/bots/api#getgamehighscores
    local success, res = api.request(
        config.endpoint .. api.token .. '/getGameHighScores',
        {
            ['user_id'] = user_id,
            ['chat_id'] = chat_id,
            ['message_id'] = message_id,
            ['inline_message_id'] = inline_message_id
        }
    )
    return success, res
end

function api.on_update(_) end
function api.on_message(_) end
function api.on_private_message(_) end
function api.on_group_message(_) end
function api.on_supergroup_message(_) end
function api.on_callback_query(_) end
function api.on_inline_query(_) end
function api.on_channel_post(_) end
function api.on_edited_message(_) end
function api.on_edited_private_message(_) end
function api.on_edited_group_message(_) end
function api.on_edited_supergroup_message(_) end
function api.on_edited_channel_post(_) end
function api.on_chosen_inline_result(_) end
function api.on_shipping_query(_) end
function api.on_pre_checkout_query(_) end
function api.on_poll(_) end
function api.on_poll_answer(_) end

function api.process_update(update)
    if update then
        api.on_update(update)
    end
    if update.message then
        if update.message.chat.type == 'private' then
            api.on_private_message(update.message)
        elseif update.message.chat.type == 'group' then
            api.on_group_message(update.message)
        elseif update.message.chat.type == 'supergroup' then
            api.on_supergroup_message(update.message)
        end
        return api.on_message(update.message)
    elseif update.edited_message then
        if update.edited_message.chat.type == 'private' then
            api.on_edited_private_message(update.edited_message)
        elseif update.edited_message.chat.type == 'group' then
            api.on_edited_group_message(update.edited_message)
        elseif update.edited_message.chat.type == 'supergroup' then
            api.on_edited_supergroup_message(update.edited_message)
        end
        return api.on_edited_message(update.edited_message)
    elseif update.callback_query then
        return api.on_callback_query(update.callback_query)
    elseif update.inline_query then
        return api.on_inline_query(update.inline_query)
    elseif update.channel_post then
        return api.on_channel_post(update.channel_post)
    elseif update.edited_channel_post then
        return api.on_edited_channel_post(update.edited_channel_post)
    elseif update.chosen_inline_result then
        return api.on_chosen_inline_result(update.chosen_inline_result)
    elseif update.shipping_query then
        return api.on_shipping_query(update.shipping_query)
    elseif update.pre_checkout_query then
        return api.on_pre_checkout_query(update.pre_checkout_query)
    elseif update.poll then
        return api.on_poll(update.poll)
    elseif update.poll_answer then
        return api.on_poll_answer
    end
    return false
end

function api.run(limit, timeout, offset, allowed_updates)
    limit = tonumber(limit) ~= nil and limit or 1
    timeout = tonumber(timeout) ~= nil and timeout or 0
    offset = tonumber(offset) ~= nil and offset or 0
    while true do
        local updates = api.get_updates(timeout, offset, limit, allowed_updates)
        if updates and type(updates) == 'table' and updates.result then
            for _, v in pairs(updates.result) do
                api.process_update(v)
                offset = v.update_id + 1
            end
        end
    end
end

function api.input_text_message_content(message_text, parse_mode, disable_web_page_preview, encoded)
    parse_mode = (type(parse_mode) == 'boolean' and parse_mode == true) and 'markdown' or parse_mode
    local input_message_content = {
        ['message_text'] = tostring(message_text),
        ['parse_mode'] = parse_mode,
        ['disable_web_page_preview'] = disable_web_page_preview
    }
    input_message_content = encoded and json.encode(input_message_content) or input_message_content
    return input_message_content
end

function api.input_location_message_content(latitude, longitude, encoded)
    local input_message_content = {
        ['latitude'] = tonumber(latitude),
        ['longitude'] = tonumber(longitude)
    }
    input_message_content = encoded and json.encode(input_message_content) or input_message_content
    return input_message_content
end

function api.input_venue_message_content(latitude, longitude, title, address, foursquare_id, encoded)
    local input_message_content = {
        ['latitude'] = tonumber(latitude),
        ['longitude'] = tonumber(longitude),
        ['title'] = tostring(title),
        ['address'] = tostring(address),
        ['foursquare_id'] = foursquare_id
    }
    input_message_content = encoded and json.encode(input_message_content) or input_message_content
    return input_message_content
end

function api.input_contact_message_content(phone_number, first_name, last_name, encoded)
    local input_message_content = {
        ['phone_number'] = tostring(phone_number),
        ['first_name'] = tonumber(first_name),
        ['last_name'] = last_name
    }
    input_message_content = encoded and json.encode(input_message_content) or input_message_content
    return input_message_content
end

function api.input_media_photo(media, caption, parse_mode)
    return {
        ['type'] = 'photo',
        ['caption'] = caption,
        ['parse_mode'] = parse_mode
    }, { ['media'] = media }
end

function api.input_media_video(media, thumb, caption, parse_mode, width, height, duration, supports_streaming)
    return {
        ['type'] = 'video',
        ['caption'] = caption,
        ['parse_mode'] = parse_mode,
        ['width'] = tonumber(width),
        ['height'] = tonumber(height),
        ['duration'] = tonumber(duration),
        ['supports_streaming'] = supports_streaming
    }, {
        ['media'] = media,
        ['thumb'] = thumb
    }
end

function api.input_media_animation(media, thumb, caption, parse_mode, width, height, duration)
    return {
        ['type'] = 'animation',
        ['caption'] = caption,
        ['parse_mode'] = parse_mode,
        ['width'] = tonumber(width),
        ['height'] = tonumber(height),
        ['duration'] = tonumber(duration)
    }, {
        ['media'] = media,
        ['thumb'] = thumb
    }
end

function api.input_media_audio(media, thumb, caption, parse_mode, duration, performer, title)
    return {
        ['type'] = 'audio',
        ['caption'] = caption,
        ['parse_mode'] = parse_mode,
        ['duration'] = tonumber(duration),
        ['performer'] = performer,
        ['title'] = title
    }, {
        ['media'] = media,
        ['thumb'] = thumb
    }
end

function api.input_media_document(media, thumb, caption, parse_mode)
    return {
        ['type'] = 'document',
        ['caption'] = caption,
        ['parse_mode'] = parse_mode
    }, {
        ['media'] = media,
        ['thumb'] = thumb
    }
end

-- Functions to handle ChatPermissions

function api.chat_permissions(can_send_messages, can_send_media_messages, can_send_polls, can_send_other_messages, can_add_web_page_previews, can_change_info, can_invite_users, can_pin_messages)
    return {
        ['can_send_messages'] = can_send_messages,
        ['can_send_media_messages'] = can_send_media_messages,
        ['can_send_polls'] = can_send_polls,
        ['can_send_other_messages'] = can_send_other_messages,
        ['can_add_web_page_previews'] = can_add_web_page_previews,
        ['can_change_info'] = can_change_info,
        ['can_invite_users'] = can_invite_users,
        ['can_pin_messages'] = can_pin_messages
    }
end

-- Functions and meta-methods for handling mask positioning arrays to use with various
-- sticker-related functions.

api.mask_position_meta = {}
api.mask_position_meta.__index = api.mask_position_meta

function api.mask_position_meta:position(point, x_shift, y_shift, scale)
    table.insert(
        self,
        {
            ['point'] = tostring(point), -- Available points include "forehead", "eyes", "mouth" or "chin".
            ['x_shift'] = tonumber(x_shift),
            ['y_shift'] = tonumber(y_shift),
            ['scale'] = tonumber(scale)
        }
    )
    return self
end

function api.mask_position()
    local output = setmetatable({}, api.mask_position_meta)
    return output
end

-- Functions for handling inline objects to use with api.answer_inline_query().

function api.send_inline_article(inline_query_id, title, description, message_text, parse_mode, reply_markup)
    description = description or title
    message_text = message_text or description
    parse_mode = (type(parse_mode) == 'boolean' and parse_mode == true) and 'markdown' or parse_mode
    return api.answer_inline_query(
        inline_query_id,
        json.encode(
            {
                {
                    ['type'] = 'article',
                    ['id'] = '1',
                    ['title'] = title,
                    ['description'] = description,
                    ['input_message_content'] = {
                        ['message_text'] = message_text,
                        ['parse_mode'] = parse_mode
                    },
                    ['reply_markup'] = reply_markup
                }
            }
        )
    )
end

function api.send_inline_article_url(inline_query_id, title, url, hide_url, input_message_content, reply_markup, id)
    return api.answer_inline_query(
        inline_query_id,
        json.encode(
            {
                {
                    ['type'] = 'article',
                    ['id'] = tonumber(id) ~= nil and tostring(id) or '1',
                    ['title'] = tostring(title),
                    ['url'] = tostring(url),
                    ['hide_url'] = hide_url or false,
                    ['input_message_content'] = input_message_content,
                    ['reply_markup'] = reply_markup
                }
            }
        )
    )
end

api.inline_result_meta = {}
api.inline_result_meta.__index = api.inline_result_meta

function api.inline_result_meta:type(type)
    self['type'] = tostring(type)
    return self
end

function api.inline_result_meta:id(id)
    self['id'] = id and tostring(id) or '1'
    return self
end

function api.inline_result_meta:title(title)
    self['title'] = tostring(title)
    return self
end

function api.inline_result_meta:input_message_content(input_message_content)
    self['input_message_content'] = input_message_content
    return self
end

function api.inline_result_meta:reply_markup(reply_markup)
    self['reply_markup'] = reply_markup
    return self
end

function api.inline_result_meta:url(url)
    self['url'] = tostring(url)
    return self
end

function api.inline_result_meta:hide_url(hide_url)
    self['hide_url'] = hide_url or false
    return self
end

function api.inline_result_meta:description(description)
    self['description'] = tostring(description)
    return self
end

function api.inline_result_meta:thumb_url(thumb_url)
    self['thumb_url'] = tostring(thumb_url)
    return self
end

function api.inline_result_meta:thumb_width(thumb_width)
    self['thumb_width'] = tonumber(thumb_width)
    return self
end

function api.inline_result_meta:thumb_height(thumb_height)
    self['thumb_height'] = tonumber(thumb_height)
    return self
end

function api.inline_result_meta:photo_url(photo_url)
    self['photo_url'] = tostring(photo_url)
    return self
end

function api.inline_result_meta:photo_width(photo_width)
    self['photo_width'] = tonumber(photo_width)
    return self
end

function api.inline_result_meta:photo_height(photo_height)
    self['photo_height'] = tonumber(photo_height)
    return self
end

function api.inline_result_meta:caption(caption)
    self['caption'] = tostring(caption)
    return self
end

function api.inline_result_meta:gif_url(gif_url)
    self['gif_url'] = tostring(gif_url)
    return self
end

function api.inline_result_meta:gif_width(gif_width)
    self['gif_width'] = tonumber(gif_width)
    return self
end

function api.inline_result_meta:gif_height(gif_height)
    self['gif_height'] = tonumber(gif_height)
    return self
end

function api.inline_result_meta:mpeg4_url(mpeg4_url)
    self['mpeg4_url'] = tostring(mpeg4_url)
    return self
end

function api.inline_result_meta:mpeg4_width(mpeg4_width)
    self['mpeg4_width'] = tonumber(mpeg4_width)
    return self
end

function api.inline_result_meta:mpeg4_height(mpeg4_height)
    self['mpeg4_height'] = tonumber(mpeg4_height)
    return self
end

function api.inline_result_meta:video_url(video_url)
    self['video_url'] = tostring(video_url)
    return self
end

function api.inline_result_meta:mime_type(mime_type)
    self['mime_type'] = tostring(mime_type)
    return self
end

function api.inline_result_meta:video_width(video_width)
    self['video_width'] = tonumber(video_width)
    return self
end

function api.inline_result_meta:video_height(video_height)
    self['video_height'] = tonumber(video_height)
    return self
end

function api.inline_result_meta:video_duration(video_duration)
    self['video_duration'] = tonumber(video_duration)
    return self
end

function api.inline_result_meta:audio_url(audio_url)
    self['audio_url'] = tostring(audio_url)
    return self
end

function api.inline_result_meta:performer(performer)
    self['performer'] = tostring(performer)
    return self
end

function api.inline_result_meta:audio_duration(audio_duration)
    self['audio_duration'] = tonumber(audio_duration)
    return self
end

function api.inline_result_meta:voice_url(voice_url)
    self['voice_url'] = tostring(voice_url)
    return self
end

function api.inline_result_meta:voice_duration(voice_duration)
    self['voice_duration'] = tonumber(voice_duration)
    return self
end

function api.inline_result_meta:document_url(document_url)
    self['document_url'] = tostring(document_url)
    return self
end

function api.inline_result_meta:latitude(latitude)
    self['latitude'] = tonumber(latitude)
    return self
end

function api.inline_result_meta:longitude(longitude)
    self['longitude'] = tonumber(longitude)
    return self
end

function api.inline_result_meta:live_period(live_period)
    self['live_period'] = tonumber(live_period)
    return self
end

function api.inline_result_meta:address(address)
    self['address'] = tostring(address)
    return self
end

function api.inline_result_meta:foursquare_id(foursquare_id)
    self['foursquare_id'] = tostring(foursquare_id)
    return self
end

function api.inline_result_meta:phone_number(phone_number)
    self['phone_number'] = tostring(phone_number)
    return self
end

function api.inline_result_meta:first_name(first_name)
    self['first_name'] = tostring(first_name)
    return self
end

function api.inline_result_meta:last_name(last_name)
    self['last_name'] = tostring(last_name)
    return self
end

function api.inline_result_meta:game_short_name(game_short_name)
    self['game_short_name'] = tostring(game_short_name)
    return self
end

function api.inline_result()
    local output = setmetatable({}, api.inline_result_meta)
    return output
end

function api.send_inline_photo(inline_query_id, photo_url, caption, reply_markup)
    return api.answer_inline_query(
        inline_query_id,
        json.encode(
            {
                {
                    ['type'] = 'photo',
                    ['id'] = '1',
                    ['photo_url'] = photo_url,
                    ['thumb_url'] = photo_url,
                    ['caption'] = caption,
                    ['reply_markup'] = reply_markup
                }
            }
        )
    )
end

function api.send_inline_cached_photo(inline_query_id, photo_file_id, caption, reply_markup)
    return api.answer_inline_query(
        inline_query_id,
        json.encode(
            {
                {
                    ['type'] = 'photo',
                    ['id'] = '1',
                    ['photo_file_id'] = photo_file_id,
                    ['caption'] = caption,
                    ['reply_markup'] = reply_markup
                }
            }
        )
    )
end

function api.url_button(text, url, encoded)
    if not text or not url then
        return false
    end
    local button = {
        ['text'] = tostring(text),
        ['url'] = tostring(url)
    }
    if encoded then
        button = json.encode(button)
    end
    return button
end

function api.callback_data_button(text, callback_data, encoded)
    if not text or not callback_data then
        return false
    end
    local button = {
        ['text'] = tostring(text),
        ['callback_data'] = tostring(callback_data)
    }
    if encoded then
        button = json.encode(button)
    end
    return button
end

function api.switch_inline_query_button(text, switch_inline_query, encoded)
    if not text or not switch_inline_query then
        return false
    end
    local button = {
        ['text'] = tostring(text),
        ['switch_inline_query'] = tostring(switch_inline_query)
    }
    if encoded then
        button = json.encode(button)
    end
    return button
end

function api.switch_inline_query_current_chat_button(text, switch_inline_query_current_chat, encoded)
    if not text or not switch_inline_query_current_chat then
        return false
    end
    local button = {
        ['text'] = tostring(text),
        ['switch_inline_query_current_chat'] = tostring(switch_inline_query_current_chat)
    }
    if encoded then
        button = json.encode(button)
    end
    return button
end

function api.callback_game_button(text, callback_game, encoded)
    if not text or not callback_game then
        return false
    end
    local button = {
        ['text'] = tostring(text),
        ['callback_game'] = tostring(callback_game)
    }
    if encoded then
        button = json.encode(button)
    end
    return button
end

function api.pay_button(text, pay, encoded)
    if not text or pay == nil then
        return false
    end
    local button = {
        ['text'] = tostring(text),
        ['pay'] = pay
    }
    if encoded then
        button = json.encode(button)
    end
    return button
end

function api.remove_keyboard(selective)
    return {
        ['remove_keyboard'] = true,
        ['selective'] = selective or false
    }
end

api.keyboard_meta = {}
api.keyboard_meta.__index = api.keyboard_meta

function api.keyboard_meta:row(row)
    table.insert(self.keyboard, row)
    return self
end

function api.keyboard(resize_keyboard, one_time_keyboard, selective)
    return setmetatable(
        {
            ['keyboard'] = {},
            ['resize_keyboard'] = resize_keyboard or false,
            ['one_time_keyboard'] = one_time_keyboard or false,
            ['selective'] = selective or false
        },
        api.keyboard_meta
    )
end

api.inline_keyboard_meta = {}
api.inline_keyboard_meta.__index = api.inline_keyboard_meta

function api.inline_keyboard_meta:row(row)
    table.insert(self.inline_keyboard, row)
    return self
end

function api.inline_keyboard()
    return setmetatable({ ['inline_keyboard'] = {} }, api.inline_keyboard_meta)
end

api.prices_meta = {}
api.prices_meta.__index = api.prices_meta

function api.prices_meta:labeled_price(label, amount)
    table.insert(
        self,
        {
            ['label'] = tostring(label),
            ['amount'] = tonumber(amount)
        }
    )
    return self
end

function api.prices()
    return setmetatable({}, api.prices_meta)
end

api.shipping_options_meta = {}
api.shipping_options_meta.__index = api.shipping_options_meta

function api.shipping_options_meta:shipping_option(id, title, prices)
    table.insert(
        self,
        {
            ['id'] = tostring(id),
            ['title'] = tostring(title),
            ['prices'] = prices
        }
    )
    return self
end

function api.shipping_options()
    return setmetatable({}, api.shipping_options_meta)
end

api.row_meta = {}
api.row_meta.__index = api.row_meta

function api.row_meta:url_button(text, url)
    table.insert(
        self,
        {
            ['text'] = tostring(text),
            ['url'] = tostring(url)
        }
    )
    return self
end

function api.row_meta:callback_data_button(text, callback_data)
    table.insert(
        self,
        {
            ['text'] = tostring(text),
            ['callback_data'] = tostring(callback_data)
        }
    )
    return self
end

function api.row_meta:switch_inline_query_button(text, switch_inline_query)
    table.insert(
        self,
        {
            ['text'] = tostring(text),
            ['switch_inline_query'] = tostring(switch_inline_query)
        }
    )
    return self
end

function api.row_meta:switch_inline_query_current_chat_button(text, switch_inline_query_current_chat)
    table.insert(
        self,
        {
            ['text'] = tostring(text),
            ['switch_inline_query_current_chat'] = tostring(switch_inline_query_current_chat)
        }
    )
    return self
end

function api.row_meta:pay_button(text, pay)
    table.insert(
        self,
        {
            ['text'] = tostring(text),
            ['pay'] = pay
        }
    )
    return self
end

function api.row(_)
    return setmetatable({}, api.row_meta)
end

api.input_media_meta = {}
api.input_media_meta.__index = api.input_media_meta

function api.input_media_meta:photo(media, caption)
    table.insert(
        self,
        {
            ['type'] = 'photo',
            ['media'] = tostring(media),
            ['caption'] = caption
        }
    )
    return self
end

function api.input_media_meta:video(media, caption, width, height, duration)
    table.insert(
        self,
        {
            ['type'] = 'video',
            ['media'] = tostring(media),
            ['caption'] = caption,
            ['width'] = width,
            ['height'] = height,
            ['duration'] = duration
        }
    )
    return self
end

function api.input_media(_)
    return setmetatable({}, api.input_media_meta)
end

function api.labeled_price(label, amount, encoded)
    if not label or not amount or tonumber(amount) == nil then
        return false
    end
    local button = {
        ['label'] = tostring(label),
        ['amount'] = tonumber(amount)
    }
    if encoded then
        button = json.encode(button)
    end
    return button
end

function api.get_chat_member_permissions(chat_id, user_id)
    if not chat_id or not user_id then
        return false
    end
    local success = api.get_chat_member(chat_id, user_id)
    if not success then
        return success
    end
    local p = success.result
    return {
        ['can_be_edited'] = p.can_be_edited or false,
        ['can_post_messages'] = p.can_post_messages or false,
        ['can_edit_messages'] = p.can_edit_messages or false,
        ['can_delete_messages'] = p.can_delete_messages or false,
        ['can_restrict_members'] = p.can_restrict_members or false,
        ['can_promote_members'] = p.can_promote_members or false,
        ['can_change_info'] = p.can_change_info or false,
        ['can_invite_users'] = p.can_invite_users or false,
        ['can_pin_messages'] = p.can_pin_messages or false,
        ['can_send_messages'] = p.can_send_messages or false,
        ['can_send_media_messages'] = p.can_send_media_messages or false,
        ['can_send_polls'] = p.can_send_polls or false,
        ['can_send_other_messages'] = p.can_send_other_messages or false,
        ['can_add_web_page_previews'] = p.can_add_web_page_previews or false
    }
end

function api.is_user_kicked(chat_id, user_id)
    if not chat_id or not user_id then
        return false
    end
    local user, res = api.get_chat_member(chat_id, user_id)
    if not user or not user.result then
        return false, res
    elseif user.result.status == 'kicked' then
        return true, res
    end
    return false, user.result.status
end

function api.is_user_group_admin(chat_id, user_id)
    if not chat_id or not user_id then
        return false
    end
    local user, res = api.get_chat_member(chat_id, user_id)
    if not user or not user.result then
        return false, res
    elseif user.result.status == ('administrator' or 'creator') then
        return true, res
    end
    return false, user.result.status
end

function api.is_user_group_creator(chat_id, user_id)
    if not chat_id or not user_id then
        return false
    end
    local user, res = api.get_chat_member(chat_id, user_id)
    if not user or not user.result then
        return false, res
    elseif user.result.status == 'creator' then
        return true, res
    end
    return false, user.result.status
end

function api.is_user_restricted(chat_id, user_id)
    if not chat_id or not user_id then
        return false
    end
    local user, res = api.get_chat_member(chat_id, user_id)
    if not user or not user.result then
        return false, res
    elseif user.result.status == 'kicked' then
        return true, res
    end
    return false, user.result.status
end

function api.has_user_left(chat_id, user_id)
    if not chat_id or not user_id then
        return false
    end
    local user, res = api.get_chat_member(chat_id, user_id)
    if not user or not user.result then
        return false, res
    elseif user.result.status == 'left' then
        return true, res
    end
    return false, user.result.status
end

return api
