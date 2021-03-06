function DATA3D_export(DATA, output_format, outputfn, output_datatype, options)


%Record original ROI
ROI = DATA.ROI;

%Check output data type
if nargin<3
    output_datatype = DATA.datatype;    
end
switch output_datatype
    case 'uint8'
       maxval = double(uint8(inf));
    case 'uint16'
       maxval = double(uint16(inf));
    otherwise
      maxval = [];
end

if nargin<5
    options = [];
end

%Check if to scale data
do_scale = 1;
if isequal(DATA.data_range, [-Inf Inf]);
   do_scale = 0; 
end
if isempty(DATA.data_range)    
    if strcmpi(DATA.data_type, 'single') | strcmpi(DATA.data_type, 'float32')     
        error('DATA3D_export:scalerequired','Scale range is required to scale floating point data.');
    else
       DATA.data_range = eval(['[' DATA.data_type '(0) ' DATA.data_type '(inf)]']);  
    end    
end
if do_scale
    scale = double(DATA.data_range);
end    

%Generate file names
n_digits = max(size(num2str(DATA.dimensions(3))));
naming_fmt = ['%0' num2str(n_digits) '.0f'];

%Check output file name and directory
sl_pos = strfind(DATA.file, '\');
do_ext = 0;
if nargin<3 | isempty(outputfn)
    do_ext = 1;
    switch DATA.contents(1)
        case 'P'
            outputfn = [DATA.file(1:sl_pos(end)) 'proj'];
        case 'R'
            outputfn = [DATA.file(1:sl_pos(end)) 'slice'];
        case 'S'
            outputfn = [DATA.file(1:sl_pos(end)) 'sinogram'];
            
    end       
end
  
am_load_label = DATA.file(sl_pos(end)+1:end);

%Check is to apply shifts
do_shifts = 0;
if ~isempty(DATA.shifts)       
    do_shifts = 1;
    xshifts = DATA.shifts(:,1);
    yshifts = DATA.shifts(:,2);
end

%Data size
imgs = DATA.ROI(1,3):DATA.ROI(2,3):DATA.ROI(3,3);
Len = DATA.ROI(1,1):DATA.ROI(2,1):DATA.ROI(3,1);
Wid = DATA.ROI(1,2):DATA.ROI(2,2):DATA.ROI(3,2);
sz = [numel(Len) numel(Wid) numel(imgs)];

avizo_load_str = '';
warning off;
img_final = [];
fn = [];
n = [];
do_avizo_script = 0;
output_order = DATA.output_order;

switch output_format
    case 'tiff'
        write = @writetiff;
        info.Format = 'tiffstack';
        avizo_load_format = 'tif';
        do_avizo_script = 1;
        
        %Check write_function to use
        if isfield(options, 'write_function')
            write_function = options.write_function;            
        else
            write_function = 'imwrite';
        end


        %set tiff properties       
        tagstruct.ImageLength = sz(1);        
        tagstruct.ImageWidth = sz(2);
        tagstruct.Photometric = 1;
        tagstruct.Compression = 1;
        tagstruct.Software = 'MATLAB:TomoTools_export';
        tagstruct.PlanarConfiguration = 1;
        tagstruct.Orientation = 5;

        %output_datatype
        switch output_datatype
            case 'uint8'
                tagstruct.BitsPerSample = 8;

            case 'uint16'
                tagstruct.BitsPerSample = 16;

            case 'float32'
                tagstruct.BitsPerSample = 32;
                tagstruct.SampleFormat = 3;
                write_function  = 'writetiff_ss_m';
        end        
        tagstruct.SamplesPerPixel = 1;
        outputfn_ext = '.tiff';
        options.stack = 1;
    case 'binary'
        write = @writebin;
        info.Format = 'binary';
        outputfn_ext = '.bin';
        if ~isfield(options, 'stack')
           options.stack = 1;
        end
    case 'am'
        
        %Check write_function to use
        if ~isfield(options, 'encoding')
            options.encoding = 'binary';            
        end 
        options.stack = 0;
        info.Format = 'am';
        write = @writeam;
        outputfn_ext = '.am'
        if do_ext
           outputfn = [outputfn '.am'];
        end
        [fid, format_str] = create_am_header;
        
    case 'overwrite'
        if isempty(DATA.write_fcn)            
            error('DATA3D_export:outputformat','Overwrite function is not specified.');           
        else
            write = @overwrite;
            do_avizo_script = 0; 
            output_datatype = 'float32';
            Len = 1:DATA.dimensions(1);
            Wid =1:DATA.dimensions(2);
            output_order = 1;
            do_scale = 0;
            do_shifts = 0;
            options.stack = 0;
            outputfn_ext = [];
        end
     
   otherwise
        error('DATA3D_export:outputformat','Output format is not recognised.');
        
end

%APPLY FILTER FUNCTION
do_filter = 0;
if isfield(options, 'filter_function')
    do_filter =1;
end

write_data;

%Write out export info
info.FileType = 'TTxml v1.0';
info.ImageHeight = sz(1);
info.ImageWidth = sz(2);
info.Datatype = output_datatype;
info.PixelSize = DATA.pixel_size;
if isprop(DATA, 'pixel_units')
    info.PixelUnits = DATA.pixel_units;
end
if isprop(DATA, 'Voltage')
    info.Voltage = DATA.Voltage;
end
if isprop(DATA, 'Current')
    info.Current = DATA.Current;
end
if isprop(DATA, 'R1')
    info.R1 = DATA.R1;
end
if isprop(DATA, 'R2')
    info.R2 = DATA.R2;
end
if isprop(DATA, 'units')
    info.Units = DATA.units;
end


sl_pos = strfind(outputfn, '\');
xml_write([outputfn(1:sl_pos(end)-1) '\export_info.xml'], info);



%write out avizo script to load image as necessary
if do_avizo_script
    hx_file = [outputfn(1:sl_pos(end)-1) '\load_data.hx'];
    fid_hx = fopen(hx_file, 'w');
    fprintf(fid_hx, '# Avizo Script\n\n');
    fprintf(fid_hx, ['[ load -' avizo_load_format ' +box ' sprintf('%g ',[0 sz(2)-1 0 sz(1)-1 0 numel(imgs)-1]*(double(DATA.pixel_size))) '+mode 2 ' avizo_load_str ' ] setLabel ' am_load_label '\n']);
    fclose(fid_hx);
end


%Write out original data header information
xml_fcn = DATA.hdr2xml_fcn;
if ~isempty(xml_fcn)
    xml_fcn(outputfn(1:sl_pos(end)-1)); 
end

warning on;

DATA.ROI = ROI;

 
        
 
%% NESTED WRITE FUNCTIONs
    function write_data
       
        
        %tagstruct.RowsPerStrip = 100000;       
        
        if output_order==-1
            %Reverse output order of reconstructed slices to prevent mirroring
            imgs = imgs(end:-1:1);    
        end
        img_count = DATA.ROI(1,3)-DATA.ROI(2,3);
        
        %LOOP OVER IMAGES
        for n = imgs
            
            %Create output file name
            img_count = img_count+DATA.ROI(2,3);
            fprintf(1, ['Writing image ' num2str(img_count) '....']);
            tic
            if options.stack
                fn = [outputfn '_' sprintf(naming_fmt, img_count) outputfn_ext];
            else
               fn = [outputfn outputfn_ext]; 
            end
            
            %Create avizo load string            
            sl_pos = strfind(fn, '\');
            if isempty(sl_pos)
                sl_pos = 0;
            end
            avizo_load_str  = [avizo_load_str '${SCRIPTDIR}/' fn(sl_pos(end)+1:end) ' '];

            %Read image
            img = double(DATA(Len,Wid,n));      
                        
            %Apply filter
            if do_filter
               img = options.filter_function(img);                
            end
            
            
            %Apply shifts if necessary
            if do_shifts
                
                %CURRENTLY SUPPORT INTEGER SHIFTS
                int_x_shift = round(xshifts(n));
                int_y_shift = round(yshifts(n));
                
                img = circshift(img, [-int_y_shift int_x_shift]);
            end


            %Scale and write images
            if strcmpi(output_datatype, 'float32');

                %Method for float32 files
                img_final = single(img);
                %write_function = 'libtiff';
            else  
                %Method of integer datatypes
                %Scale

                if do_scale
                    img = maxval*(img-scale(1))/(scale(2)-scale(1));
                end

                %Write output
                switch output_datatype
                    case 'uint8'
                        img_final = uint8(img);
                    case 'uint16'
                        img_final = uint16(img);
                    case 'single'
                        img_final = single(img);                    
                end        

            end   
            
            write();

            t = toc;
            fprintf(1, ['Done in ' num2str(t) 's\n']);
        end
    end


%% NESTED AM FUNCTIONS
%Create AM header---------------------------------------------------------
    function [fid_am, format_str] = create_am_header
        %Check if header exists
        hdr_am = amheader_create(outputfn, sz, output_datatype, double(DATA.pixel_size), options.encoding);   
        output_datatype_am = hdr_am.Variables.Lattice.Data.Datatype;

        %Add extra information to Parameters
        if ~isempty(DATA.pixel_units)
            hdr_am.Parameters.Units.Value = DATA.pixel_units;
        end
        %hdr_am.Parameters.Source.Value = ['TomoTools: ' DATA.file];

        %Replace single \ with double in file name
        %hdr_am.Parameters.Source.Value = strrep(hdr_am.Parameters.Source.Value, '\', '\\');

        %Write header-------------------------------------------------------------
        %Open file
        fid_am = fopen(outputfn, 'w');

        %Write file type
        fprintf(fid_am, ['# AmiraMesh ' hdr_am.FileType '\n\n']);


        %Write variable dimensions
        fn = fieldnames(hdr_am.Variables);
        n_names = size(fn,1);

        for m = 1:n_names   
           fprintf(fid_am, ['define ' fn{m} ' ' sprintf('%u ',hdr_am.Variables.(fn{m}).Dimensions) '\n']);    
        end

        fprintf(fid_am, '\n\n');

        %Write out parameters
        param_str = 'Parameters {\n|ip|\n}';
        n_blanks = 4;
        curr_obj = hdr_am.Parameters;
        depth = 0;
        output_str = get_format_str(curr_obj, param_str,depth, 0);
        fprintf(fid_am, output_str);


        %Write out variable info
        fprintf(fid_am, '\n\n');
        for m = 1:n_names
            fn_sub = fieldnames(hdr_am.Variables.(fn{m}));

            for k = 1:size(fn_sub,1)

                obj = hdr_am.Variables.(fn{m}).(fn_sub{k});
                if isstruct(obj)

                   str = [fn{m} ' { ' obj.Datatype ' ' fn_sub{k} ' } ' obj.Value];

                   if ~isempty(obj.Info)
                       tmp = [str '(' obj.Info ')']; 
                       str = tmp;
                   end    
                   fprintf(fid_am, [str '\n']);
                end
            end
        end


        %Write out data info-----------------------------------------------
        ft = strfind(hdr_am.FileType, 'ASCII');
        fprintf(fid_am, '\n\n@1\n');
        if ft
          %ASCII encoding
          %Determine format
           switch output_datatype_am
                case 'byte'           
                   format_str = '%hu';        
                case 'short'
                   format_str = '%hi';

                case 'ushort'
                   format_str = '%hu';   

                case 'int'
                   format_str = '%u';

                case 'float32'
                   format_str = '%tu';

                case 'float64'
                   format_str = '%bu';
            end
        else           
           switch output_datatype_am
                 case 'byte'           
                    format_str = 'uint8';        
                 case 'short'
                    format_str = 'int16';                   
                 case 'ushort'
                    format_str = 'uint16';                   
                 case 'int'
                    format_str = 'int32';                   
                 case 'float32'
                    format_str = 'single';
                 case 'float64'
                    format_str = 'double';
           end
        end            


    end

    function param_str = get_format_str(curr_obj, param_str,depth, islast)

        n_blanks = 4;
        fn_param = fieldnames(curr_obj);
        
        n_child = size(fn_param,1);
                
        for p = 1:n_child
            curr_depth = depth+1;
    
            %Determine if current object contains substructures
            if ~isstruct(curr_obj.(fn_param{p})) || strcmpi(fn_param{p}, 'Value')
                %No sub structures
                val = curr_obj.(fn_param{p});
                if isnumeric(val);
                    val = strtrim(sprintf('%g ',val));
                else
                    tmp = ['"' val '"'];
                    val = tmp;
                end    
                
                if strcmpi(fn_param{p}, 'Value')
                    nm_str = '';
                    blnk_str = '';
                else
                    
                   nm_str = fn_param{p};
                   blnk_str = repmat(' ',1,curr_depth*n_blanks);
                end    
                
                %Find insertion point
                ip = strfind(param_str, '|ip|');
                ip = ip(1);
                
                if ~islast
                    %Do comma & keep insertion point 
                    curr_str = [blnk_str nm_str '' val ',\n|ip|'];                   
                else
                    %Omit comma
                    curr_str = [blnk_str nm_str '' val ''];
                end   
                
                %Length of new string
                str_len = length(param_str)+length(curr_str)-4;
                
                %Insert new string
                output_str = repmat(' ', 1, str_len);
                output_str(1:ip-1) = param_str(1:ip-1);
                output_str(ip:ip+length(curr_str)-1) = curr_str;
                output_str(ip+length(curr_str):end) = param_str(ip+4:end);
                
                param_str = output_str;
                
            else
                %Insert open brackets
                
                ip = strfind(param_str, '|ip|');
                ip = ip(1);
                blnk_str = repmat(' ',1,curr_depth*n_blanks);
                
                ch_fn = fieldnames(curr_obj.(fn_param{p}));
                
                if size(ch_fn,1)==1 && strcmpi(ch_fn{1}, 'Value')
                    
                    curr_str = [blnk_str fn_param{p} ' |ip|'];
                
                else
                    if islast || p==n_child
                        curr_str = [blnk_str fn_param{p} ' {\n|ip|\n' blnk_str '}'];                        
                    else
                        curr_str = [blnk_str fn_param{p} ' {\n|ip|\n' blnk_str '}\n|ip|'];
                    end   
                end
                
                %Length of new string
                str_len = length(param_str)+length(curr_str)-4;
                
                %Insert new string
                output_str = repmat(' ', 1, str_len);
                output_str(1:ip-1) = param_str(1:ip-1);
                
                output_str(ip:ip+length(curr_str)-1) = curr_str;  
                output_str(ip+length(curr_str):end) = param_str(ip+4:end);
                
                param_str = output_str;
                               
                %Recursive call to this function
                curr_obj_new = curr_obj.(fn_param{p});
                param_str = get_format_str(curr_obj_new, param_str,curr_depth, p==n_child);
                
            end
            
            
        end    
    end

    function  writeam
        switch options.encoding
            case 'ascii'

                fprintf(fid, format_str, img_final);

            case 'binary'
                
                fwrite(fid, img_final, format_str);

            case 'rle'

                %NOT CURRENTLY SUPPORTED

            case 'zip'
                %NOT CURRENTLY SUPPORTED  
        end
        if n==imgs(end)            
           fclose(fid); 
        end
            
    end 



%% NESTED BIN FUNCTIONS
    function writebin
        
        switch options.stack
            case 1
                %binary stack
                do_avizo_script = 1;
                fid = fopen(fn,'w');
                fwrite(fid, img_final, output_datatype);
                fclose(fid);             
            case 0
                %binary vol
                if n==imgs(1)
                   fid = fopen(fn,'w+'); 
                end
                fwrite(fid, img_final, output_datatype);                
                if n==imgs(end)                   
                   fclose(fid); 
                end
        end
    end


%% NESTED TIFF FUNCTIONS
    function writetiff
        
        %Write image to tiff file
         switch write_function
              case 'libtiff'
                  %Open tiff file for writing
                    tiff_file = Tiff(fn, 'w');
                    tiff_file.setTag(tagstruct);

                    %Write image
                    tiff_file.write(img_final);
                    tiff_file.close();
              case 'imwrite'

                    %Write image
                    imwrite(img_final, fn, 'tiff', 'compression', 'none');
                    %writetiff_ss_m(fn, img_final);
              case 'writetiff_ss_m'   
                     writetiff_ss_m(fn, img_final);
         end
   
    end


%% NESTED OVERWRITE FUNCTIONS
    function overwrite
        
        %Undo flat field
        if DATA.apply_ff & DATA.apply_ff_default             
            img_final = img_final.*double(DATA.reference_img);
        end
        
        %Undo rot90
        if DATA.rotby90 & DATA.rotby90_default           
            img_final = img_final.';
            img_final = img_final(:,end:-1:1);
        end
      
        %change data type
        switch output_datatype
           case 'uint8'
                img_final = uint8(img_final);
            case 'uint16'
                 img_final = uint16(img_final);
            case 'single'
                img_final = single(img_final);                    
        end
        
        %Write data        
        feval(DATA.write_fcn,img_final,n)        
        
    end

end