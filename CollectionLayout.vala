
public abstract class LayoutItem : Gtk.Alignment {
    public static const int LABEL_PADDING = 4;
    public static const int FRAME_PADDING = 4;
    public static const string TEXT_COLOR = "#FFF";
    public static const string SELECTED_COLOR = "#FF0";
    public static const string UNSELECTED_COLOR = "#FFF";
    
    // Due to the potential for thousands or tens of thousands of thumbnails being present in a
    // particular view, all widgets used here and by subclasses should be NOWINDOW widgets.
    protected Gtk.Image image = new Gtk.Image();
    protected Gtk.Label title = new Gtk.Label("");
    protected Gtk.Frame frame = new Gtk.Frame(null);
    
    private bool selected = false;
    
    public LayoutItem() {
        // bottom-align everything
        set(0, 1, 0, 0);
        
        title.set_use_underline(false);
        title.set_justify(Gtk.Justification.LEFT);
        title.set_alignment(0, 0);
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(TEXT_COLOR));
        
        Gtk.Widget panel = get_control_panel();

        // store everything in a vbox, with the expandable image on top followed by a widget
        // on the bottom for display and controls
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.set_border_width(FRAME_PADDING);
        vbox.pack_start(image, false, false, 0);
        vbox.pack_end(title, false, false, LABEL_PADDING);
        if (panel != null)
            vbox.pack_end(panel, false, false, 0);
        
        // surround everything with a frame
        frame.set_shadow_type(Gtk.ShadowType.NONE);
        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
        frame.add(vbox);

        add(frame);
    }
    
    public Gtk.Widget? get_control_panel() {
        return null;
    }
    
    public abstract Gdk.Pixbuf? get_full_pixbuf();
    
    public abstract Exif.Orientation get_orientation();
    
    public abstract void set_orientation(Exif.Orientation orientation);
    
    public virtual void exposed() {
    }
    
    public virtual void unexposed() {
    }

    public virtual void select() {
        selected = true;

        frame.set_shadow_type(Gtk.ShadowType.OUT);
        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(SELECTED_COLOR));
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(SELECTED_COLOR));
        
        Gtk.Widget panel = get_control_panel();
        if (panel != null)
            panel.modify_fg(Gtk.StateType.NORMAL, parse_color(SELECTED_COLOR));
    }

    public virtual void unselect() {
        selected = false;

        frame.set_shadow_type(Gtk.ShadowType.NONE);
        frame.modify_bg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
        title.modify_fg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));

        Gtk.Widget panel = get_control_panel();
        if (panel != null)
            panel.modify_fg(Gtk.StateType.NORMAL, parse_color(UNSELECTED_COLOR));
    }

    public bool toggle_select() {
        if (selected) {
            unselect();
        } else {
            select();
        }
        
        return selected;
    }

    public bool is_selected() {
        return selected;
    }
}

public class CollectionLayout : Gtk.Layout {
    public static const int TOP_PADDING = 16;
    public static const int BOTTOM_PADDING = 16;
    public static const int ROW_GUTTER_PADDING = 24;

    // the following are minimums, as the pads and gutters expand to fill up the window width
    public static const int LEFT_PADDING = 16;
    public static const int RIGHT_PADDING = 16;
    public static const int COLUMN_GUTTER_PADDING = 24;
    
    private Gee.ArrayList<LayoutItem> items = new Gee.ArrayList<LayoutItem>();

    public CollectionLayout() {
        modify_bg(Gtk.StateType.NORMAL, AppWindow.BG_COLOR);
        expose_event += on_expose;
        size_allocate += on_resize;
    }
    
    public void append(LayoutItem item) {
        items.add(item);

        // need to do this to have its size requisitioned in refresh()
        item.show_all();
    }
    
    public void remove_item(LayoutItem item) {
        items.remove(item);
        remove(item);
    }
    
    public LayoutItem? get_item_at(double xd, double yd) {
        int x = (int) xd;
        int y = (int) yd;

        foreach (LayoutItem item in items) {
            Gtk.Allocation alloc = item.allocation;
            if ((x >= alloc.x) && (y >= alloc.y) && (x <= (alloc.x + alloc.width))
                && (y <= (alloc.y + alloc.height))) {
                return item;
            }
        }
        
        return null;
    }
    
    public void clear() {
        foreach (LayoutItem item in items) {
            remove(item);
        }
        
        items.clear();
    }
    
    public void refresh() {
        if (items.size == 0)
            return;

        // don't bother until layout is of some appreciable size
        if (allocation.width <= 1)
            return;
            
        // Step 1: Determine the widest row in the layout, and from it the number of columns
        int x = LEFT_PADDING;
        int col = 0;
        int maxCols = 0;
        int rowWidth = 0;
        int widestRow = 0;

        foreach (LayoutItem item in items) {
            // perform size requests first time through, but not thereafter
            Gtk.Requisition req;
            item.size_request(out req);
                
            // carriage return (i.e. this item will overflow the view)
            if ((x + req.width + RIGHT_PADDING) > allocation.width) {
                if (rowWidth > widestRow) {
                    widestRow = rowWidth;
                    maxCols = col;
                }
                
                col = 0;
                x = LEFT_PADDING;
                rowWidth = 0;
            }
            
            x += req.width + COLUMN_GUTTER_PADDING;
            rowWidth += req.width;
            
            col++;
        }
        
        // account for dangling last row
        if (rowWidth > widestRow) {
            widestRow = rowWidth;
            maxCols = col;
        }
        
        assert(maxCols > 0);
        
        // Step 2: Now that the number of columns is known, find the maximum height for each row
        // and the maximum width for each column
        int row = 0;
        int tallest = 0;
        int totalWidth = 0;
        col = 0;
        int[] columnWidths = new int[maxCols];
        int[] rowHeights = new int[(items.size / maxCols) + 1];
        int gutter = 0;
        
        for (;;) {
            foreach (LayoutItem item in items) {
                Gtk.Requisition req = item.requisition;
                
                if (req.height > tallest)
                    tallest = req.height;
                
                // store largest thumb size of each column as well as track the total width of the
                // layout (which is the sum of the width of each column)
                if (columnWidths[col] < req.width) {
                    totalWidth -= columnWidths[col];
                    columnWidths[col] = req.width;
                    totalWidth += req.width;
                }

                if (++col >= maxCols) {
                    col = 0;
                    rowHeights[row++] = tallest;
                    tallest = 0;
                }
            }
            
            // account for final dangling row
            if (col != 0)
                rowHeights[row] = tallest;
            
            // Step 3: Calculate the gutter between the items as being equidistant of the
            // remaining space (adding one gutter to account for the right-hand one)
            gutter = (allocation.width - totalWidth) / (maxCols + 1);
            
            // if only one column, gutter size could be less than minimums
            if (maxCols == 1)
                break;

            // have to reassemble if the gutter is too small ... this happens because Step One
            // takes a guess at the best column count, but when the max. widths of the columns are
            // added up, they could overflow
            if ((gutter < LEFT_PADDING) || (gutter < RIGHT_PADDING) || (gutter < COLUMN_GUTTER_PADDING)) {
                maxCols--;
                col = 0;
                row = 0;
                tallest = 0;
                totalWidth = 0;
                columnWidths = new int[maxCols];
                rowHeights = new int[(items.size / maxCols) + 1];
                debug("refresh(): readjusting columns: maxCols=%d", maxCols);
            } else {
                break;
            }
        }

        /*
        debug("refresh(): width:%d totalWidth:%d maxCols:%d gutter:%d", allocation.width, totalWidth, 
            maxCols, gutter);
        */

        // Step 4: Lay out the items in the space using all the information gathered
        x = gutter;
        int y = TOP_PADDING;
        col = 0;
        row = 0;

        foreach (LayoutItem item in items) {
            Gtk.Requisition req = item.requisition;

            // this centers the item in the column
            int xpadding = (columnWidths[col] - req.width) / 2;
            assert(xpadding >= 0);
            
            // this bottom-aligns the item along the row
            int ypadding = (rowHeights[row] - req.height);
            assert(ypadding >= 0);
            
            // if item was recently appended, it needs to be put() rather than move()'d
            if (item.parent == (Gtk.Widget) this) {
                move(item, x + xpadding, y + ypadding);
            } else {
                put(item, x + xpadding, y + ypadding);
            }

            x += columnWidths[col] + gutter;

            // carriage return
            if (++col >= maxCols) {
                x = gutter;
                y += rowHeights[row] + ROW_GUTTER_PADDING;
                col = 0;
                row++;
            }
        }
        
        // Step 5: Define the total size of the page as the size of the allocated width and
        // the height of all the items plus padding
        set_size(allocation.width, y + rowHeights[row] + BOTTOM_PADDING);
    }

    private int lastWidth = 0;
    
    private void on_resize() {
        // only refresh() if the width has changed
        if (allocation.width != lastWidth) {
            lastWidth = allocation.width;
            refresh();
        }
    }
    
    private bool on_expose(CollectionLayout cl, Gdk.EventExpose event) {
        Gdk.Rectangle visibleRect = Gdk.Rectangle();
        visibleRect.x = (int) get_hadjustment().get_value();
        visibleRect.y = (int) get_vadjustment().get_value();
        visibleRect.width = allocation.width;
        visibleRect.height = allocation.height;

        /*
        debug("on_client_exposed x:%d y:%d w:%d h:%d", visibleRect.x, visibleRect.y,
            visibleRect.width, visibleRect.height);
        */
        
        Gdk.Rectangle bitbucket = Gdk.Rectangle();
        int exposedCount = 0;
        int unexposedCount = 0;

        foreach (LayoutItem item in items) {
            if (visibleRect.intersect((Gdk.Rectangle) item.allocation, bitbucket)) {
                item.exposed();
                exposedCount++;
            } else {
                item.unexposed();
                unexposedCount++;
            }
        }
        
        /*
        debug("exposed:%d unexposed:%d", exposedCount, unexposedCount);
        */

        return false;
    }
}