extends Node

## Embedded content: `ENTRIES` maps almanac topic titles → BBCode strings (no CSV). Edit here or migrate to CSV later.
## Broader orientation: docs/CODEBASE_GUIDE.md (section 5).

const ENTRIES: Dictionary = {
	"Stacking in Space": "In a natural forest, plants do not compete on a single flat plane; they stack vertically to maximise sunlight and space. \n\n[b]Canopy:[/b] Large, deep-rooted perennial trees. They provide the main yield but cast shadows.\n[b]Understory:[/b] Shade-tolerant shrubs and bushes that thrive in the dappled light of the canopy.\n[b]Groundcover:[/b] Low-lying plants that hug the earth, acting as a living mulch to lock in moisture and suppress weeds.",

	"Earthworks & Water": "Water is the most precious resource on the farm. Rather than letting rain run off, we sculpt the earth to slow it, spread it, and sink it.\n\n[b]Swales:[/b] Trenches dug on contour. They catch water and slowly release a hydration plume into the downhill soil, protecting crops during dry midsummer weather.\n[b]Mounds:[/b] Raised earth (often built over rotting wood) that stays dry on top but acts like a sponge underneath.",

	"Soil Succession": "You cannot plant a food forest in dead clay. The earth must be healed first.\n\n[b]Pioneers:[/b] Hardy plants like Daikon Radish or Broad Beans. Their roots physically shatter compacted soil and fix nitrogen.\n[b]Chop and Drop:[/b] Using a scythe to cut down pioneers and leave their biomass on the ground. This turns them into a rich biological fertiliser, permanently upgrading the soil to support demanding perennial trees.",

	"Animal Tractors": "In a healthy ecosystem, animals are workers, not just products.\n\n[b]Pig Tractors:[/b] Pigs naturally root up the soil. By fencing them into overgrown areas, you harness their natural behaviour to clear weeds, till the earth, and heavily fertilise the ground, prepping it perfectly for immediate planting.",

	"Zones of Use": "Permaculture design organises the farm by frequency of use to save human energy.\n\n[b]Zone 0:[/b] The farmhouse. The centre of activity.\n[b]Zone 1:[/b] The area immediately surrounding the house. Reserved for crops that need daily attention (like delicate annuals or herb gardens).\n[b]Zone 4/5:[/b] The wild edges. Left largely untouched to support foraging and native wildlife.",

	"Guilds & Synergy": "Plants grow better in communities. A 'Guild' is a carefully chosen cluster of plants that mutually support one another.\n\nFor example, planting an Apple Tree (heavy feeder) alongside Broad Beans (nitrogen fixer) and Daikon Radish (clay breaker) creates a 'Superguild'. The beans feed the tree, the radish opens the soil for water, and the entire system grows significantly faster than a tree planted in isolation.",

	"Superguild: Three Sisters Core": "Requires: 1x Tall Support, 1x Legume, 1x Groundcover within a 3x3 area.\n\nThe oldest guild in the Americas. The tall support lifts the legume's leaves into the sun whilst the groundcover locks moisture below. A self-sustaining loop that provides a x1.4 Yield Multiplier.",
	
	"Superguild: Orchard Core Guild": "Requires: 1x Fruit Tree, 1x Dynamic Accumulator, 1x Nitrogen Fixer within a 3x3 area.\n\nThe classic permaculture orchard trio. The nitrogen fixer restores what the fruit tree plunders and the dynamic accumulator mines deep minerals. Provides a massive x1.8 Yield Multiplier.",
	
	"Superguild: Riparian Windbreak": "Requires: 1x Nitrogen Fixer, 1x Wetland, 1x Windbreak within a 3x3 area.\n\nAlder's Frankia root bacteria activate when a windbreak shelters wet ground from drying winds. Highly resistant to evaporation.",
	
	"Superguild: Temperate Orchard Stack": "Requires: 1x Fruit Tree, 1x Nitrogen Fixer, 1x Dynamic Accumulator within a 3x3 area.\n\nWhen comfrey mines deep minerals and a nitrogen fixer restores what the fruit tree draws, the guild reaches full potential. Triggers a x2.0 yield multiplier, but fails rapidly if the comfrey dies.",

	"Living Soil & Biodiversity": "Dirt is just ground-up rock; soil is alive. The long-term health of your farm depends entirely on the microscopic life beneath your feet.\n\n[b]The Mycorrhizal Network:[/b] Soil with high Biodiversity acts as an invisible shield and a free fertiliser. If a plant is placed in highly biodiverse earth, the soil web will provide its water and nitrogen for free!\n[b]Building Life:[/b] Planting 'Nitrogen Fixers' or 'Dynamic Accumulators' (like Comfrey) will slowly heal the earth, raising its Biodiversity over time.",

	"Aeration & Root Depth": "Roots need to breathe, and different plants have different strategies for piercing the earth.\n\n[b]Fibrous Roots:[/b] Plants with shallow, spreading roots (like grasses and lettuces) don't mind compacted soil. They are perfect pioneers for hard dirt.\n[b]Taproots:[/b] Deep-rooted plants (like large trees or carrots) will struggle and grow at half-speed in compacted earth. To accelerate their growth, plant them on highly aerated earthworks like [b]Hugelbeds[/b]!"
}
