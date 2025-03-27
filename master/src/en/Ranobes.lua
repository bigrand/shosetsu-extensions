-- {"id":96201,"ver":"1.0.2","libVer":"1.0.0","author":"bigrand","dep":["dkjson"]}

local baseURL = "https://ranobes.top"
local imageURL = "https://github.com/bigrand/shosetsu-extensions/raw/master/icons/ranobes.png"

local json = Require("dkjson")

local fetchedPageCounters = {}

local function prettyPrint(label, value)
    print("\n==============================================")
    print(">> " .. label .. ":")
    print(tostring(value))
    print("==============================================\n")
end

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

local function randomizedDelay()
	---@diagnostic disable-next-line: undefined-global
	delay(math.random(4000, 6000))
end

local function fetchSafely(url, saveChapters)
	local ok, document = pcall(GETDocument, url)

	if not ok then
		local errMsg = tostring(document)
		local code = errMsg:match("(%d%d%d)")

		if saveChapters then
			return false, code or "unknown", errMsg
		end

		if code == "429" then
			error("Rate limit reached. Use WebView to unblock or try later.")
		elseif code then
			error("HTTP error: " .. code)
		else
			error("HTTP error detected:\n" .. errMsg)
		end
	end

	local titleTag = document:selectFirst("title")
	if titleTag and titleTag:text() == "Error" then
		if saveChapters then
			return false, "captcha", "CAPTCHA detected."
		end
		error("CAPTCHA detected. Use WebView to bypass.")
	end

	return document
end


local function getIndexData(indexDocument)
	local data = tostring(indexDocument:select("main + script"))
	:gsub("<script.-%s*>", "")
	:gsub("</script>", "")
	:gsub("window.__DATA__ = ", "")

	--prettyPrint("String Data", data)
	local obj, pos, err = json.decode(data)

	if err then
		error("JSON Decode Error: " .. err)
	else
		local jsonData = json.encode(obj, { indent = true })
		--prettyPrint("JSON Data", jsonData)
		return obj
	end
end

local function parseListing(document)
	return map(document:select(".rank-story"), function(v)
		local title = v:selectFirst("h2 a")
		local figure = v:selectFirst("figure")

		local img = figure and figure:selectFirst("img")
		local imgURL = expandURL(img:attr("src"))

		---@diagnostic disable-next-line: deprecated, missing-fields
		return Novel({
			title = title:text(),
			link = shrinkURL(title:attr("href")),
			imageURL = imgURL,
		})
	end)
end

local function parseChapters(indexDocument)
	local indexData = getIndexData(indexDocument)

	local chapterPattern = "[Cc][Hh][Aa][Pp]%a*%.?[%s%-:]+([0-9]+%.?[0-9]*)"
  	local episodePattern = "[Ee][Pp]%a*%.?[%s%-:]+([0-9]+%.?[0-9]*)"

	-- prettyPrint("CHAPTERS", "RETRIEVED CORRECTLY!")

	return map(indexData.chapters, function(chapter)
		local chapterTitle = chapter.title
		-- prettyPrint("CHAPTER TITLE", chapterTitle .. "\n" .. "LINK: " .. chapter.link)
		return NovelChapter {
			order = tonumber(chapter.id) or 0,
			title = chapter.title,
			link = chapter.link,
			release = chapter.showDate .. " • " .. chapter.date,
			sourceId = chapter.id,
		}
	end)
end

local function parseNovel(novelURL, loadChapters)
	local url = expandURL(novelURL)
	-- prettyPrint("URL", url)
	local document = fetchSafely(url)
	assert(document, "Document should not be nil.")

	local title = document:selectFirst('meta[property="og:title"]'):attr("content")
	-- prettyPrint("Title", title)

	local altTitle = document:selectFirst("h1.title > span.subtitle"):text()
	-- prettyPrint("Alternate Title", altTitle)

	local imgURL = document:selectFirst("a.highslide"):attr("href")
	-- prettyPrint("Image URL", imgURL)

	local description = tostring(document:selectFirst(".moreless.cont-text.showcont-h"))
	-- prettyPrint("Description [BEFORE]", description)
	description = HTMLFormatToString(description)
	-- prettyPrint("Description [AFTER]", description)

	local status = document:selectFirst("div.r-fullstory-spec > ul > li:nth-of-type(2) > span > a")
	if not status then
		status = document:selectFirst("div.r-fullstory-spec > ul > li > span > a"):text()
	else
		status = status:text()
	end
	-- prettyPrint("Status", status)

	local genres = map(document:select("#mc-fs-genre > div.links"):select("a"), toText)
	-- prettyPrint("Genres", table.concat(genres, ", "))

	local authors = map(document:select(".tag_list"):select("a"), toText)
	-- prettyPrint("Authors", table.concat(authors, ", "))

	local tags = map(document:select(".cont-in > div.cont-text.showcont-h"):select("a"), toText)
	-- prettyPrint("Tags", table.concat(tags, ", "))

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
	-- prettyPrint("Chapter Count", chapterCount)

	local commentCount = tonumber(document:select("div.r-fullstory-spec > ul:nth-child(3) > li > span > a"):text())
	-- prettyPrint("Comment Count", commentCount)

	local viewCount = tonumber((document:select("div.r-fullstory-spec > ul:nth-child(2) > li:nth-child(2) > span"):text():gsub(" ", "")))
	-- prettyPrint("View Count", viewCount)

	local chapterIndexUrl = expandURL(document:select(".uppercase.bold:nth-of-type(2)"):attr("href"))
	-- prettyPrint("Chapter Index URL", chapterIndexUrl)

	---@diagnostic disable-next-line: missing-fields
	local NovelInfo = NovelInfo {
		title = title,
		alternativeTitles = { altTitle },
		link = novelURL,
		imageURL = imgURL,
		language = "eng",
		description = description,
		status = ({
			Active = NovelStatus.PUBLISHING,
			Completed = NovelStatus.COMPLETED,
		})[status] or NovelStatus.UNKNOWN,
		tags = tags,
		genres = genres,
		authors = authors,
		viewCount = viewCount,
		commentCount = commentCount
	}

	if loadChapters then
		local totalPages = math.ceil(chapterCount / 25)
		-- prettyPrint("TOTAL PAGES", totalPages)
		local chapters = {}

		if not fetchedPageCounters[novelURL] then
			fetchedPageCounters[novelURL] = { fetchedCount = 0, totalPages = totalPages }
		end

		local counterData = fetchedPageCounters[novelURL]

		-- prettyPrint("FETCHED PAGE COUNTER", counterData.fetchedCount)

		if counterData.fetchedCount == 0 then
			local lastIndexDocument = fetchSafely(chapterIndexUrl .. "page/" .. totalPages, true)

			-- prettyPrint("NOTICE", "Attempting to parse lastIndexDocument chapters!")
			local lastIndexChapters = parseChapters(lastIndexDocument)

			chapters = concatLists(chapters, lastIndexChapters)
			counterData.fetchedCount  = counterData.fetchedCount  + 1
			-- prettyPrint("SAVED PAGE COUNTER", counterData.fetchedCount)
		end

		local remainingPages = totalPages - counterData.fetchedCount

		if remainingPages < 1 then
			counterData.fetchedCount = counterData.fetchedCount - 1
			remainingPages = 1
		end

		for i = remainingPages, 1, -1 do
			local next, errType, errMsg = fetchSafely(chapterIndexUrl .. "page/" .. i, true)
		
			if next then
				local nextChapters = parseChapters(next)
				chapters = concatLists(chapters, nextChapters)
				counterData.fetchedCount = counterData.fetchedCount + 1
				randomizedDelay()
			else
				NovelInfo:setChapters(AsList(chapters))
		
				local errorMessages = {
					["429"] = 'Rate limit reached. Enter "Chapter List" to bypass block or try later.',
					["captcha"] = 'CAPTCHA detected. Enter "Chapter List" to bypass block using WebView.'
				}
		
				error(errorMessages[errType] or ("HTTP error " .. errType .. ": " .. errMsg))
			end
		end

		NovelInfo:setChapters(AsList(chapters))
	end

	return NovelInfo
end

local function getPassage(chapterURL)
	-- prettyPrint("TRYING TO FETCH CHAPTER - URL", chapterURL)
	local document = GETDocument(chapterURL)
	local title = document:selectFirst("#dle-speedbar > span"):text()
	local chapter = document:selectFirst("#arrticle.text")

	chapter:prepend("<h1>" .. title .. "</h1>")

	return pageOfElem(chapter, false)
end

local function search(data)
	local queryContent = data[QUERY]
    local page = data[PAGE]
	local document = GETDocument(baseURL .. "/search/" .. queryContent .. "/page/" .. page)

    return map(document:select(".shortstory"), function(v)
		local title = v:selectFirst("h2 a"):text()
		local link = shrinkURL(v:selectFirst("h2 a"):attr("href"))
		local imgURl = v:selectFirst("figure"):attr("style"):match("url%((.-)%)")
		
		-- prettyPrint("NOVEL FOUND!", "Title: " .. title .. "\n" .. "imgURL: " .. imgURl .. "\n" .. "Link: " .. link)

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
			return parseListing(fetchSafely(expandURL("/ranking/")))
		end),
	},

	shrinkURL = shrinkURL,
	expandURL = expandURL,
	getPassage = getPassage,
	parseNovel = parseNovel,
	search = search,
}