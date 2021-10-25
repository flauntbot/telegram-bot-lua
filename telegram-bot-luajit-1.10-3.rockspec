package = "telegram-bot-luajit"
version = "1.10-3"

source = {
    url = "ssh://git@scm.opengress.net:59922/diffusion/117/telegram-bot-luajit.git",
    dir = "telegram-bot-luajit",
    branch = "main"
}

description = {
    summary = "A simple yet extensive Lua library for the Telegram bot API.",
    detailed = "A simple yet extensive Lua library for the Telegram bot API, with many tools and API-friendly functions. Compatible with LuaJIT",
    license = "GPL-3",
    homepage = "https://scm.opengress.net/diffusion/117/",
    maintainer = "Chris <dpkg@chris-nz.com>"
}

supported_platforms = {
    "linux",
    "macosx",
    "unix",
    "bsd"
}

dependencies = {
    "dkjson >= 2.5-2",
    "lpeg >= 1.0.1-1",
    "luasec >= 0.6-1",
    "luasocket >= 3.0rc1-2",
    "multipart-post >= 1.1-1",
    "luautf8 >= 0.1.1-1",
    "html-entities >= 1.3.1-0"
}

build = {
    type = "builtin",
    modules = {
        ["telegram-bot-luajit.config"] = "telegram-bot-luajit/config.lua",
        ["telegram-bot-luajit.core"] = "telegram-bot-luajit/core.lua",
        ["telegram-bot-luajit.tools"] = "telegram-bot-luajit/tools.lua",
        ["telegram-bot-luajit.b64url"] = "telegram-bot-luajit/b64url.lua"
    }
}
