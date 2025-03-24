-- {"id":96203,"ver":"1.0.2","libVer":"1.0.0","author":"bigrand","dep":["dkjson"]}

local baseURL = "https://ranobes.top"
local imageURL = "https://github.com/bigrand/shosetsu-extensions/raw/master/icons/ranobes.png"

local json = Require("dkjson")

local function prettyPrint(label, value)
    local divider = string.rep("=", 46)
    print("\n" .. divider)
    print(">> " .. label .. ":")

    if type(value) == "table" then
        print(json.encode(value, { indent = true }))
    else
        print(tostring(value))
    end

    print(divider .. "\n")
end

local function concatTables(list1, list2)
    for i = 1, #list2 do
		if not list1[list2[i]] then
			table.insert(list1, list2[i])
		end
    end
    return list1
end

local function trim(s)
	return s:match("^%s*(.-)%s*$")
end

local function HTMLFormatToString(text)
	text = text:gsub(">%s+<", "><")

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

local function mapNotNull(o, f)
    local result = {}
    for i, v in ipairs(o) do
        local mapped = f(v)
        if mapped ~= nil then
            table.insert(result, mapped)
        end
    end
    return result
end

local function randomizedDelay()
	---@diagnostic disable-next-line: undefined-global
	delay(math.random(241, 653))
end

local function safeFetch(url)
	local ok, document = pcall(GETDocument, url)
	if not ok then
		local errMsg = tostring(document)
		local code = errMsg:match("(%d%d%d)")

		if code == "429" then
			error("Rate limit reached. Try again later.")
		else
			error("HTTP error: " .. (code or errMsg))
		end
	end

	local title = document:selectFirst("title"):text()
	if title == "Error" or title == "Ranobes Flood Guard" then
		error("CAPTCHA detected. Use WebView to bypass. (or a Browser)")
	end

	return document
end

local function parseListing(url, data)
    local page = data[PAGE]
	local document = safeFetch(url .. "page/" .. page)
	local pageNovels = document:selectFirst("#dle-content")
	prettyPrint("CURRENT PAGE", page)
	return map(pageNovels:select("article.block.story.shortstory.mod-poster"), function(v)
		local title = v:selectFirst(".title"):text()
		local link = v:selectFirst("h2 > a"):attr("href")
		local figure = v:selectFirst(".cover")
		local imgURL = figure and figure:attr("style"):match("url%((.-)%)")

		---@diagnostic disable-next-line: deprecated, missing-fields
		return Novel({
			title = title,
			link = shrinkURL(link),
			imageURL = imgURL,
		})
	end)
end

local function parseNovel(novelURL, loadChapters)
	local url = expandURL(novelURL)
	prettyPrint("URL", url)
	local document = safeFetch(url)
	assert(document, "parseNovel: Document should not be nil.")
	-- prettyPrint("DOCUMENT", document)

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

	local chapterCount = tonumber(document:select("div.r-fullstory-spec > ul:first-of-type > li:nth-of-type(4) > span"):text():match("^(%d+)"))
	-- prettyPrint("Chapter Count", chapterCount)

	local commentCount = tonumber(document:select("div.r-fullstory-spec > ul:nth-child(3) > li > span > a"):text())
	-- prettyPrint("Comment Count", commentCount)

	local viewCount = tonumber((document:select("div.r-fullstory-spec > ul:nth-child(2) > li:nth-child(2) > span"):text():gsub(" ", "")))
	-- prettyPrint("View Count", viewCount)


	-- local chapterIndexUrl = expandURL(document:select(".uppercase.bold:nth-of-type(2)"):attr("href"))
	-- prettyPrint("Chapter Index URL", chapterIndexUrl)

	local novelID = tonumber(document:selectFirst('meta[property="og:url"]'):attr("content"):match("/novels/(%d+)-"))
	prettyPrint("NovelID", novelID)

	local mtlURL = "https://ranobes.top/mtl-reader/" .. novelID .. "/index/"

	---@diagnostic disable-next-line: missing-fields
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
	-- prettyPrint("TRYING TO FETCH CHAPTER - URL", chapterURL)
	local document = safeFetch(chapterURL)
	local chapter = document:selectFirst("#arrticle.text")

	return pageOfElem(chapter, false)
end

local function search(data)
	local queryContent = data[QUERY]
    local page = data[PAGE]
	local document = safeFetch(baseURL .. "/f/g.mtl_files=1/l.title=" .. queryContent .. "/sort=date/order=desc/page/" .. page)
	local pageNovels = document:selectFirst("#dle-content")

	prettyPrint("CURRENT PAGE SEARCH", page)

	return map(pageNovels:select("article.block.story.shortstory.mod-poster"), function(v)
		local title = v:selectFirst(".title"):text()
		local link = v:selectFirst("h2 > a"):attr("href")
		local figure = v:selectFirst(".cover")
		local imgURL = figure and figure:attr("style"):match("url%((.-)%)")

		---@diagnostic disable-next-line: deprecated, missing-fields
		return Novel({
			title = title,
			link = shrinkURL(link),
			imageURL = imgURL,
		})
	end)
end

return {
	id = 96203,
	name = "Ranobes",
	baseURL = baseURL,
	imageURL = imageURL,
	hasCloudFlare = true,
	hasSearch = true,
	chapterType = ChapterType.HTML,

	listings = {
		Listing("Popular", true, function(data)
			return parseListing(expandURL("/f/g.mtl_files=1/sort=date/order=desc/"), data)
		end),
	},

	shrinkURL = shrinkURL,
	expandURL = expandURL,
	getPassage = getPassage,
	parseNovel = parseNovel,
	search = search,
}