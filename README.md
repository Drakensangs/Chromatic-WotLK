# 🎨 **Chromatic** (WotLK 3.3.5a)

A lightweight addon that color codes elemental damage/resistances in item & spell tooltips, color codes item tooltip borders based on rarity, and class names in item tooltips.

# ✨ **Features**

**Item tooltip class name colors.** Class restriction lines (for example `Class: Warrior`) on item tooltips have each class name colored in its official class color.

**Item tooltip rarity borders.** Borders are colored based on the item's rarity.

**Color coded damage/resistance type.** Tooltip lines containing damage/resistance types are colored automatically. Fire, Frost, Arcane, Holy, Nature, and Shadow each get color coded.

# ⚙️ **Slash Commands**

Type  `/chromatic` or `/chrc` and one of these commands:

`class`   - toggle item tooltip class name color coding

`border`  - toggle color coded item tooltip borders

`element` - toggle damage/resistance type color coding

`status`  - show current addon settings

# 🔌 **Addon Compatibility**

Chromatic detects and color codes tooltips from the following addons:

**AtlasLoot**

**AtlasQuest**

**aux**

**ElvUI**

# **⚠️ Known Issues**

Element color coding is not context-aware — any occurrence of Fire, Frost, Arcane, Holy, Nature, or Shadow in a tooltip will be colorized, including spell names, item names, and even mob names. An exception list file exists but is not exhaustive. I've been very strict with phrases that should be exluded from being colorized, but if you've think it's too much, you can easily edit `Exceptions.lua`.

# 👨‍💻 **Author**
Drakensangs

## 📸 **Screenshots**

<img width="347" height="96" alt="chromaticssspell" src="https://github.com/user-attachments/assets/ae0b0479-e8fc-4a10-942c-727c5b7ff4d4" />
<img width="377" height="183" alt="chromaticssspell1" src="https://github.com/user-attachments/assets/0bf4627f-7214-4c5d-acd2-dd6b9be487bf" />
<img width="428" height="162" alt="chromaticsstoken" src="https://github.com/user-attachments/assets/bb4fa53d-32a7-46da-aa61-f645b2b0636e" />
<img width="450" height="663" alt="chromaticsstier" src="https://github.com/user-attachments/assets/2f3eceae-3461-4a7f-a967-3a066b88c5d5" />
<img width="521" height="507" alt="chromaticsssm" src="https://github.com/user-attachments/assets/7f337ade-61c4-4ce4-b115-e3693c074d76" />
<img width="698" height="348" alt="chromaticssaux" src="https://github.com/user-attachments/assets/6be21101-8520-492c-a159-b5b7d01973fa" />
<img width="402" height="496" alt="chromaticsselvui" src="https://github.com/user-attachments/assets/7948c5ab-cd02-4705-ae90-25279ebdb779" />


