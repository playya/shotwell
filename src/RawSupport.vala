/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

#if !NO_RAW

public class RawFileFormatDriver : PhotoFileFormatDriver {
    private static RawFileFormatDriver instance = null;
    
    public static RawFileFormatDriver get_instance() {
        lock (instance) {
            if (instance == null)
                instance = new RawFileFormatDriver();
        }
        
        return instance;
    }
    
    public override PhotoFileFormatProperties get_properties() {
        return RawFileFormatProperties.get_instance();
    }
    
    public override PhotoFileReader create_reader(string filepath) {
        return new RawReader(filepath);
    }
    
    public override PhotoMetadata create_metadata() {
        return new PhotoMetadata();
    }
    
    public override bool can_write() {
        return false;
    }
    
    public override PhotoFileWriter? create_writer(string filepath) {
        return null;
    }
    
    public override PhotoFileSniffer create_sniffer(File file, PhotoFileSniffer.Options options) {
        return new RawSniffer(file, options);
    }
}

public class RawFileFormatProperties : PhotoFileFormatProperties {
    private static string[] KNOWN_EXTENSIONS = {
        "3fr", "arw", "srf", "sr2", "bay", "crw", "cr2", "cap", "iiq", "eip", "dcs", "dcr", "drf",
        "k25", "kdc", "dng", "erf", "fff", "mef", "mos", "mrw", "nef", "nrw", "orf", "ptx", "pef",
        "pxn", "r3d", "raf", "raw", "rw2", "raw", "rwl", "rwz", "x3f"
    };
    
    private static RawFileFormatProperties instance = null;
    
    public static RawFileFormatProperties get_instance() {
        lock (instance) {
            if (instance == null)
                instance = new RawFileFormatProperties();
        }
        
        return instance;
    }
    
    public override PhotoFileFormat get_file_format() {
        return PhotoFileFormat.RAW;
    }

    public override string get_user_visible_name() {
        return _("RAW");
    }

    public override PhotoFileFormatFlags get_flags() {
        return PhotoFileFormatFlags.MIMIC_RECOMMENDED;
    }
    
    public override string get_default_extension() {
        // Because RAW is a smorgasbord of file formats and exporting to a RAW file is
        // not expected, this function should probably never be called.  However, need to pick
        // one, so here it is.
        return "raw";
    }
    
    public override string[] get_known_extensions() {
        return KNOWN_EXTENSIONS;
    }
}

public class RawSniffer : PhotoFileSniffer {
    public RawSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }
    
    public override DetectedPhotoInformation? sniff() throws Error {
        DetectedPhotoInformation detected = new DetectedPhotoInformation();
        
        GRaw.Processor processor = new GRaw.Processor();
        processor.output_params->user_flip = GRaw.Flip.NONE;
        
        try {
            processor.open_file(file.get_path());
            processor.unpack();
            processor.adjust_sizes_info_only();
        } catch (GRaw.Exception exception) {
            if (exception is GRaw.Exception.UNSUPPORTED_FILE)
                return null;
            
            throw exception;
        }
        
        detected.image_dim = Dimensions(processor.get_sizes().iwidth, processor.get_sizes().iheight);
        detected.colorspace = Gdk.Colorspace.RGB;
        detected.channels = 3;
        detected.bits_per_channel = 8;
        
        RawReader reader = new RawReader(file.get_path());
        try {
            detected.metadata = reader.read_metadata();
        } catch (Error err) {
            // ignored
        }
        
        if (detected.metadata != null) {
            uint8[]? flattened_sans_thumbnail = detected.metadata.flatten_exif(false);
            if (flattened_sans_thumbnail != null && flattened_sans_thumbnail.length > 0)
                detected.exif_md5 = md5_binary(flattened_sans_thumbnail, flattened_sans_thumbnail.length);
            
            uint8[]? flattened_thumbnail = detected.metadata.flatten_exif_preview();
            if (flattened_thumbnail != null && flattened_thumbnail.length > 0)
                detected.thumbnail_md5 = md5_binary(flattened_thumbnail, flattened_thumbnail.length);
        }
        
        if (calc_md5)
            detected.md5 = md5_file(file);
        
        detected.format_name = "raw";
        detected.file_format = PhotoFileFormat.RAW;
        
        return detected;
    }
}

public class RawReader : PhotoFileReader {
    public RawReader(string filepath) {
        base (filepath, PhotoFileFormat.RAW);
    }
    
    public override PhotoMetadata read_metadata() throws Error {
        PhotoMetadata metadata = new PhotoMetadata();
        metadata.read_from_file(get_file());
        
        return metadata;
    }
    
    public override Gdk.Pixbuf unscaled_read() throws Error {
        GRaw.Processor processor = new GRaw.Processor();
        processor.configure_for_rgb_display(false);
        processor.output_params->user_flip = GRaw.Flip.NONE;
        
        processor.open_file(get_filepath());
        processor.unpack();
        processor.process();
        
        return processor.make_mem_image().get_pixbuf_copy();
    }
    
    public override Gdk.Pixbuf scaled_read(Dimensions full, Dimensions scaled) throws Error {
        double width_proportion = (double) scaled.width / (double) full.width;
        double height_proportion = (double) scaled.height / (double) full.height;
        bool half_size = width_proportion < 0.5 && height_proportion < 0.5;
        
        GRaw.Processor processor = new GRaw.Processor();
        processor.configure_for_rgb_display(half_size);
        processor.output_params->user_flip = GRaw.Flip.NONE;
        
        processor.open_file(get_filepath());
        processor.unpack();
        processor.process();
        
        GRaw.ProcessedImage image = processor.make_mem_image();
        
        return resize_pixbuf(image.get_pixbuf_copy(), scaled, Gdk.InterpType.BILINEAR);
    }
}

#endif