-- {"id":96203,"ver":"1.0.3","libVer":"1.0.0","author":"bigrand","dep":["dkjson"]}

local baseURL = "https://ranobes.top"
local imageURL = "https://github.com/bigrand/shosetsu-extensions/raw/master/icons/ranobes.png"

local json = Require("dkjson")

local consecutiveTriggers = 0
local function randomizedDelay()
    consecutiveTriggers = consecutiveTriggers + 1
    local delayTime
    if consecutiveTriggers <= 2 then
        delayTime = math.random(500, 1500)
    else
        delayTime = math.random(1500, 3000)
    end
    delay(delayTime)
end

local function trim(s)
	return s:match("^%s*(.-)%s*$")
end

local function HTMLToString(text)
	text = text:gsub(">%s+<", "><")
	text = text:gsub("&nbsp;", " ")

	local brTag = "%s*<[Bb][Rr]%s*(/?)%s*>%s*"
	local pattern2 = brTag .. brTag .. "(" .. brTag .. ")*"

	text = text:gsub(pattern2, "[[BRBR]]")
	text = text:gsub(brTag, "\n")
	text = text:gsub("</[Pp]>", "\n\n")
	text = text:gsub("<[^>]+>", "")
	text = text:gsub("%[%[BRBR%]%]", "\n\n")

	local lines = {}

	for line in (text .. "\n"):gmatch("(.-)\n") do
	table.insert(lines, trim(line))
	end
	text = table.concat(lines, "\n")
	text = trim(text)

	return text
end

local function shrinkURL(url)
	return url:gsub(baseURL, "")
end

local function expandURL(url)
	return baseURL .. url
end

local toText = function(v)
    return v:text()
end

local function safeFetch(url, saveChapters)
	local ok, document = pcall(GETDocument, url)

	if not ok then
		local errMsg = tostring(document)
		local code = errMsg:match("(%d%d%d)")

		if saveChapters then
			return false, code or "unknown", errMsg
		end

		if code == "429" then
			error("Rate limit reached. Try again later.")
		else
			error("HTTP error: " .. (code or errMsg))
		end
	end

	local title = document:selectFirst("title"):text()
	if title == "Error" or title == "Ranobes Flood Guard" then
		if saveChapters then
			return false, "captcha", "CAPTCHA detected."
		end

		error("CAPTCHA detected. Use WebView to bypass. (or a Browser)")
	end

	return document
end

local function parseListing(data, isSearch)
    local page = data[PAGE]
    local url

    if isSearch then
        local queryContent = data[QUERY]
        url = baseURL .. "/f/g.mtl_files=1/l.title=" .. queryContent .. "/sort=date/order=desc/page/" .. page
    else
        url = baseURL .. "/f/g.mtl_files=1/sort=date/order=desc/page/" .. page
    end

	randomizedDelay()
    local document = GETDocument(url)
    local pageNovels = document:selectFirst("#dle-content")
    return map(pageNovels:select("article.block.story.shortstory.mod-poster"), function(v)
        local title = v:selectFirst(".title"):text()
        local link = v:selectFirst("h2 > a"):attr("href")
        local figure = v:selectFirst(".cover")
        local imgURL = figure and figure:attr("style"):match("url%((.-)%)")
        
        return Novel({
            title = title,
            link = shrinkURL(link),
            imageURL = imgURL,
        })
    end)
end

local function parseNovel(novelURL, loadChapters)
	local url = expandURL(novelURL)
	local document = safeFetch(url)
	
	if not document then
		error("Error: Failed to fetch novel.")
	end
	local title = document:selectFirst('meta[property="og:title"]'):attr("content")
	local altTitle = document:selectFirst("h1.title > span.subtitle"):text()
	local imgURL = document:selectFirst("a.highslide"):attr("href")

	local description = tostring(document:selectFirst(".moreless.cont-text.showcont-h"))
	description = HTMLToString(description)

	local status = document:selectFirst("div.r-fullstory-spec > ul > li:nth-of-type(2) > span > a")
	if not status then
		status = document:selectFirst("div.r-fullstory-spec > ul > li > span > a"):text()
	else
		status = status:text()
	end

	local genres = map(document:select("#mc-fs-genre > div.links"):select("a"), toText)
	local authors = map(document:select(".tag_list"):select("a"), toText)
	local tags = map(document:select(".cont-in > div.cont-text.showcont-h"):select("a"), toText)
	local commentCount = tonumber(document:select("div.r-fullstory-spec > ul:nth-child(3) > li > span > a"):text())
	local viewCount = tonumber((document:select("div.r-fullstory-spec > ul:nth-child(2) > li:nth-child(2) > span"):text():gsub(" ", "")))
	local novelID = tonumber(document:selectFirst('meta[property="og:url"]'):attr("content"):match("/novels/(%d+)-"))
	local mtlURL = "https://ranobes.top/mtl-reader/" .. novelID .. "/index/"

	local NovelInfo = NovelInfo {
		title = title,
		alternativeTitles = { altTitle },
		link = mtlURL,
		imageURL = imgURL,
		language = "eng",
		description = description,
		status = ({
			Active = NovelStatus.PUBLISHING,
			Ongoing = NovelStatus.PUBLISHING,
			Completed = NovelStatus.COMPLETED,
			Break = NovelStatus.PAUSED,
			Hiatus = NovelStatus.PAUSED
		})[status] or NovelStatus.UNKNOWN,
		tags = tags,
		genres = genres,
		authors = authors,
		viewCount = viewCount,
		commentCount = commentCount
	}

	if loadChapters then
		local chapters = {}
		local chaptersIndex = safeFetch(mtlURL):selectFirst("#dle-content")

		chapters = map(chaptersIndex:select("a:has(> div.mtl_chapters)"), function (chapter)
			local title = chapter:selectFirst(".title"):text()
			local href = chapter:attr("href")
			local link = expandURL(href)
			local order = link:match(".-/(%d+)/[^/]+/$")

			return NovelChapter {
				order = order,
				title = title,
				link = link,
			}
		end)

		NovelInfo:setChapters(chapters)
	end

	return NovelInfo
end

local function getPassage(chapterURL)
	local document = safeFetch(chapterURL)
	local chapter = document:selectFirst("#arrticle.text")

	return pageOfElem(chapter, false)
end

return {
	id = 96203,
	name = "Ranobes (MTL)",
	baseURL = baseURL,
	imageURL = imageURL,
	hasCloudFlare = true,
	hasSearch = true,
	chapterType = ChapterType.HTML,

	listings = {
		Listing("Popular", true, function(data)
			return parseListing(data, false)
		end),
	},

	shrinkURL = shrinkURL,
	expandURL = expandURL,
	getPassage = getPassage,
	parseNovel = parseNovel,
	search = function(data)
		return parseListing(data, true)
	end,
}