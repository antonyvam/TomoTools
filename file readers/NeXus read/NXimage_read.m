function img = NXimage_read(foh, image_no, apply_ref, rotby90,image_key)

%Check which images to load
if nargin<5
    image_key = 0;
end
if nargin<4
    rotby90 = 1;
end
if nargin<3
    apply_ref = 1;
end

%Check if flat field exists
if apply_ref & ~isfield(foh, 'Reference')
    warning('NXIMAGE_READ:noflatfield','Cannot apply reference correction as it cannot be found.');
    apply_ref=0;
end 

%Determine image size
if isequal(size(image_no),[2 3])
      image_no = image_no(:,[2 1 3]); %Undo rot90
      ROI_start = [image_no(1,1) image_no(1,2) image_no(1,3)];
      ROI_start(ROI_start<1)=1;
      ROI_end = [image_no(2,1) image_no(2,2) image_no(2,3)];
      ROI_end(1) = min(ROI_end(1),foh.ImageWidth);
      ROI_end(2) = min(ROI_end(2),foh.ImageHeight);
      ROI_end(3) = min(ROI_end(3),foh.NoOfImages);
else
    ROI_start = [1 1 image_no(1)];
    ROI_end = [foh.ImageWidth foh.ImageHeight image_no(end)];    
      
    
%     img = [];
%     if nimgs>1
%         for k = 1:nimgs
%            if isempty(img)           
%                 img = repmat(NXimage_read(foh, image_no(k), apply_ff, rotby90,image_key), [1 1 nimgs]);        
%            else
%                img(:,:,k) = NXimage_read(foh, image_no(k), apply_ff, rotby90,image_key);
%            end
%         end
%         return;
% 
%     end
end

key_inds = find(foh.ImageKey==image_key);
try
   ROI_start(3) = key_inds(ROI_start(3));
   ROI_end(3) = key_inds(ROI_end(3));
    %curr_key = key_inds(image_no);
catch
   error('NXIMAGE_READ:noimage', 'Image does not exist');
   return;
end

readimage;
%imager(img)

if apply_ref
    img = double(img);
    for n = 1:size(img,3)
        if strcmpi(foh.Reference.BlackRefs.Mode, 'single')
        img(:,:,n) = double(img(:,:,n))-double(foh.Reference.BlackRefs.Data(ROI_start(1):ROI_end(1),ROI_start(2):ROI_end(2)));
        
        end
        if strcmpi(foh.Reference.WhiteRefs.Mode, 'single')
        img(:,:,n) = double(img(:,:,n))./double(foh.Reference.WhiteRefs.Data(ROI_start(1):ROI_end(1),ROI_start(2):ROI_end(2)));        
        end
    end
end
%Rotate by 90 degrees

if rotby90
    if size(img,3)==1
        img = img.';
        %img =img(end:-1:1,:);
    else
       img = permute(img, [2 1 3]);
        
    end
end

    function readimage
        
       
       img = h5read(foh.DataFile{1},foh.DataFile{2},ROI_start,ROI_end-ROI_start+1);      
       %img = h5read(foh.DataFile{1},foh.DataFile{2},[1 1 curr_key],[img_size 1]);
        
        
    end






end