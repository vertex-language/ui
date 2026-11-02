package window

/// One thing in a menu: an item, or a separator between them.
public struct MenuItem {
    public var Title: string
    /// The key that chooses it with Command: "n". "" for none.
    public var Shortcut: string
    /// What a menuCommand event says it was.
    public var Id: int32
    public var Enabled: bool
    public var IsSeparator: bool

    public init(title: string, id: int32, shortcut: string = "", enabled: bool = true) {
        Title = title
        Id = id
        Shortcut = shortcut
        Enabled = enabled
        IsSeparator = false
    }

    public static let separator: MenuItem = {
        var m = MenuItem(title: "", id: 0)
        m.IsSeparator = true
        return m
    }()
}

public struct Menu {
    public var Title: string
    public var Items: [MenuItem]

    public init(title: string, items: [MenuItem]) {
        Title = title
        Items = items
    }
}

func specLine(item: MenuItem) -> string {
    if item.IsSeparator { return "-" }
    return "\(item.Title)\t\(item.Shortcut)\t\(item.Id)\t\(item.Enabled ? 1 : 0)"
}

/// Puts menus in the menu bar, after the application's own. They replace
/// those set before.
public func SetMenus(menus: [Menu]) {
    var lines: [string] = []
    for m in menus {
        lines.append("#" + m.Title)
        for i in m.Items { lines.append(specLine(i)) }
    }
    winSetMenus(lines.joined(separator: "\n"))
}

/// Puts an item in the system's status bar, its menu these; a title of ""
/// takes it away.
public func SetStatusItem(title: string, items: [MenuItem] = []) {
    winSetStatusItem(title, items.map { specLine($0) }.joined(separator: "\n"))
}

/// How many menus SetMenus has put in the bar.
public func MenuCount() -> int32 { return winMenuCount() }

/// Chooses a menu's item as a click would. Answers whether it was there.
public func ChooseMenuItem(menu: int32, item: int32) -> bool { return winChooseMenuItem(menu, item) != 0 }
