-- {"id":96201,"ver":"1.0.4","libVer":"1.0.0","author":"bigrand","dep":["dkjson"]}

local baseURL = "https://ranobes.top"
local imageURL = "https://github.com/bigrand/shosetsu-extensions/raw/master/icons/ranobes.png"

local json = Require("dkjson")

local fetchedPageCounters = {}

local function concatLists(list1, list2)
    for i = 1, #list2 do
        table.insert(list1, list2[i])
    end
    return list1
end

local function trim(s)
	return s:match("^%s*(.-)%s*$")
end

local function HTMLFormatToString(text)
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

local consecutiveTriggers = 0
local function randomizedDelay(isSearch)
	local delayTime

	if isSearch then
		consecutiveTriggers = consecutiveTriggers + 1
		if consecutiveTriggers <= 2 then
			delayTime = math.random(1000, 2000)
		else
			delayTime = math.random(3000, 4000)
		end
	else
		delayTime = math.random(2000, 3000)
	end

	delay(delayTime)
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

local function getIndexData(indexDocument)
	local data = tostring(indexDocument:select("main + script"))
	:gsub("<script.-%s*>", "")
	:gsub("</script>", "")
	:gsub("window.__DATA__ = ", "")

	local obj, pos, err = json.decode(data)

	if err then
		error("JSON Decode Error: " .. err)
	else
		local jsonData = json.encode(obj, { indent = true })
		return obj
	end
end

local function parseListing(url)
	randomizedDelay(true)
	local document = safeFetch(url)

	if not document then
		error("Error: Failed to fetch listing.")
	end

	return map(document:select(".rank-story"), function(v)
		local title = v:selectFirst("h2 a")
		local figure = v:selectFirst("figure")

		local img = figure and figure:selectFirst("img")
		local imgURL = expandURL(img:attr("src"))

		return Novel({
			title = title:text(),
			link = shrinkURL(title:attr("href")),
			imageURL = imgURL,
		})
	end)
end

local function parseChapters(indexDocument)
	local indexData = getIndexData(indexDocument)

	return map(indexData.chapters, function(chapter)
		local dateNumber = chapter.date:gsub("%D", "")
		local orderNumber = tonumber(dateNumber .. chapter.id) or 0

		return NovelChapter {
			order = orderNumber,
			title = chapter.title,
			link = chapter.link,
			release = chapter.showDate .. " • " .. chapter.date,
			sourceId = chapter.id,
		}
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
	description = HTMLFormatToString(description)

	local status = document:selectFirst("div.r-fullstory-spec > ul > li:nth-of-type(2) > span > a")
	if not status then
		status = document:selectFirst("div.r-fullstory-spec > ul > li > span > a"):text()
	else
		status = status:text()
	end

	local genres = map(document:select("#mc-fs-genre > div.links"):select("a"), toText)
	local authors = map(document:select(".tag_list"):select("a"), toText)
	local tags = map(document:select(".cont-in > div.cont-text.showcont-h"):select("a"), toText)

	local chapterCount
	local liNodes = document:select("div.r-fullstory-spec > ul:first-of-type > li")
	for i = 1, liNodes:size() do
		local li = liNodes:get(i - 1)
		local text = li:text()
		if text:find("Available:") or text:find("Translated:") then
			chapterCount = tonumber(text:match("(%d+)"))
			break
		end
	end

	local commentCount = tonumber(document:select("div.r-fullstory-spec > ul:nth-child(3) > li > span > a"):text())
	local viewCount = tonumber((document:select("div.r-fullstory-spec > ul:nth-child(2) > li:nth-child(2) > span"):text():gsub(" ", "")))
	local chapterIndexUrl = expandURL(document:select(".uppercase.bold:nth-of-type(2)"):attr("href"))

	local NovelInfo = NovelInfo {
		title = title,
		alternativeTitles = { altTitle },
		link = novelURL,
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
		local totalPages = math.ceil(chapterCount / 25)
		local chapters = {}

		if not fetchedPageCounters[novelURL] then
			fetchedPageCounters[novelURL] = { fetchedCount = 0, totalPages = totalPages }
		end

		local counterData = fetchedPageCounters[novelURL]

		if counterData.fetchedCount == 0 then
			local lastIndexDocument = safeFetch(chapterIndexUrl .. "page/" .. totalPages, true)
			local lastIndexChapters = parseChapters(lastIndexDocument)

			chapters = concatLists(chapters, lastIndexChapters)
			counterData.fetchedCount  = counterData.fetchedCount  + 1
		end

		local remainingPages = totalPages - counterData.fetchedCount

		for i = remainingPages, 1, -1 do
			randomizedDelay()
			local next, errType, errMsg = safeFetch(chapterIndexUrl .. "page/" .. i, true)

			if next then
				local nextChapters = parseChapters(next)
				chapters = concatLists(chapters, nextChapters)
				counterData.fetchedCount = counterData.fetchedCount + 1
			else
				NovelInfo:setChapters(AsList(chapters))
				break
			end
		end

		NovelInfo:setChapters(AsList(chapters))
	end

	return NovelInfo
end

local function getPassage(chapterURL)
	local document = safeFetch(chapterURL)

	if not document then
		error("Error: Failed to fetch passage.")
	end

	local title = document:selectFirst("#dle-speedbar > span"):text()
	local chapter = document:selectFirst("#arrticle.text")

	chapter:prepend("<h1>" .. title .. "</h1>")

	return pageOfElem(chapter, false)
end

local function search(data)
	local queryContent = data[QUERY]
    local page = data[PAGE]

	randomizedDelay(true)
	local document = GETDocument(baseURL .. "/search/" .. queryContent .. "/page/" .. page)

    return map(document:select(".shortstory"), function(v)
		local title = v:selectFirst("h2 a"):text()
		local link = shrinkURL(v:selectFirst("h2 a"):attr("href"))
		local imgURl = v:selectFirst("figure"):attr("style"):match("url%((.-)%)")

		return Novel({
			title = title,
			link = link,
			imageURL = imgURl
		})
	end)
end

return {
	id = 96201,
	name = "Ranobes",
	baseURL = baseURL,
	imageURL = imageURL,
	hasCloudFlare = true,
	hasSearch = true,
	chapterType = ChapterType.HTML,

	listings = {
		Listing("Popular", false, function()
			return parseListing(expandURL("/ranking/"))
		end),
	},

	shrinkURL = shrinkURL,
	expandURL = expandURL,
	getPassage = getPassage,
	parseNovel = parseNovel,
	search = search,
}