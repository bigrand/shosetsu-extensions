-- {"id":42042069,"ver":"1.2.5","libVer":"1.0.0","author":"Doomsdayrs","dep":["url>=1.0.0"]}

local baseURL = "https://yomou.syosetu.com"
local passageURL = "https://ncode.syosetu.com"
local encode = Require("url").encode

local function getTotalPages(html)
	local lastPageLink = html:select(".c-pager__item--last"):attr("href")
	if lastPageLink then
		local totalPages = tonumber(lastPageLink:match("p=(%d+)"))
		return totalPages or 1
	end
	return 1
end

---@param url string
local function shrinkURL(url)
	return url:gsub(passageURL, "")
end

---@param url string
local function expandURL(url)
	return passageURL .. url
end

local function search(data)
	local url = baseURL .. "/search.php?&word=" .. encode(data[0]) .. "&type=re&p=" .. data[PAGE]
	local document = GETDocument(url)


	return map(document:select("div.searchkekka_box"), function(v)
		local novel = Novel()
		local e = v:selectFirst("div.novel_h"):selectFirst("a.tl")
		novel:setLink(shrinkURL(e:attr("href")))
		novel:setTitle(e:text())
		return novel
	end)
end

local function parseListing(filter, data)
	if data[PAGE] == 0 then
		data[PAGE] = 1
	end

	local url = baseURL .. filter .. data[PAGE]
	local document = GETDocument(url)

	return map(document:select("div.searchkekka_box"), function(v)
		local novel = Novel()
		local e = v:selectFirst("div.novel_h"):selectFirst("a.tl")
		novel:setLink(shrinkURL(e:attr("href")))
		novel:setTitle(e:text())
		return novel
	end)
end

return {
	id = 42042069,
	name = "SyosetsuB",
	baseURL = baseURL,
	imageURL = "https://github.com/shosetsuorg/extensions/raw/dev/icons/Syosetsu.png",

	listings = {
		Listing("Most Weekly Views", true, function(data)
			return parseListing("/search.php?type=re&order=weekly&p=", data)
		end),
		Listing("Latest Published", true, function(data)
			return parseListing("/search.php?type=re&order=new&notnizi=1&p=", data)
		end),
		Listing("Most Bookmarked", true, function(data)
			return parseListing("/search.php?type=re&order=favnovelcnt&p=", data)
		end),
		Listing("Most Reviews", true, function(data)
			return parseListing("/search.php?type=re&order=reviewcnt&p=", data)
		end),
		Listing("Highest Overall Points", true, function(data)
			return parseListing("/search.php?type=re&order=hyoka&p=", data)
		end),
		Listing("Highest Daily Points", true, function(data)
			return parseListing("/search.php?type=re&order=dailypoint&p=", data)
		end),
		Listing("Highest Weekly Points", true, function(data)
			return parseListing("/search.php?type=re&order=weeklypoint&p=", data)
		end),
		Listing("Highest Monthly Points", true, function(data)
			return parseListing("/search.php?type=re&order=monthlypoint&p=", data)
		end),
		Listing("Highest Quarterly Points", true, function(data)
			return parseListing("/search.php?type=re&order=quarterpoint&p=", data)
		end),
		Listing("Highest Yearly Points", true, function(data)
			return parseListing("/search.php?type=re&order=yearlypoint&p=", data)
		end),
		Listing("Most Raters", true, function(data)
			return parseListing("/search.php?type=re&order=hyokacnt&p=", data)
		end),
		Listing("Most Words", true, function(data)
			return parseListing("/search.php?type=re&order=lengthdesc&p=", data)
		end),
		Listing("Oldest Published", true, function(data)
			return parseListing("/search.php?type=re&order=generalfirstup&p=", data)
		end),
		Listing("Oldest Updates", true, function(data)
			return parseListing("/search.php?type=re&order=old&p=", data)
		end)
	},

	-- Default functions that had to be set
	getPassage = function(chapterURL)
		local document = GETDocument(passageURL .. chapterURL)
		local e = document:selectFirst(".p-novel")
		if not e then
			return "INVALID PARSING, CONTACT DEVELOPERS"
		end
		return table.concat(map(e:select("p"), function(v)
			return v:text()
		end), "\n") :gsub("<br>", "\n\n")
	end,

	parseNovel = function(novelURL, loadChapters)
		local novelPage = NovelInfo()
		local document = GETDocument(passageURL .. novelURL)

		novelPage:setAuthors({ document:selectFirst(".p-novel__author a"):text()})
		novelPage:setTitle(document:selectFirst(".p-novel__title"):text())

		-- Description
		local e = document:selectFirst(".p-novel__summary")
		if e then
			novelPage:setDescription(tostring(e):gsub("<br%s*/?>", "\n")
			:gsub("<[^>]->", "")                     
			:gsub("\n%s*\n+", "\n\n")       
			:gsub("^%s+", ""):gsub("%s+$", ""))
		end
		-- Chapters
		if loadChapters then
			local chapters = {}
			local totalPages = getTotalPages(document)
			for page = 1, totalPages do
				local pageURL = novelURL .. "?p=" .. page

				local pageDocument = GETDocument(passageURL .. pageURL)
				map(pageDocument:select(".p-eplist__sublist"), function(v)
					local chap = NovelChapter()
					local title = v:selectFirst("a"):text()
					local link = v:selectFirst("a"):attr("href")
					local release = v:selectFirst(".p-eplist__update"):text()

					chap:setTitle(title)
					chap:setLink(link)
					chap:setRelease(release)
					table.insert(chapters, chap)
				end)
			end
			novelPage:setChapters(AsList(chapters))
		end

		return novelPage
	end,
	shrinkURL = shrinkURL,
	expandURL = expandURL,
	getTotalPages = getTotalPages,
	search = search,
}
