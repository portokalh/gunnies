function [ ] = Optimal_4D_Bilateral_Point_Filter(files, mask, outname)
% files{2} => the file to be filtered
% mask => a binary mask used to define the subregion to filter
% xsize, ysize, zsize => unmasked file dimensions
% w => filter raidus
% outpath => location for the filtered data
% total_time => total time to perform the bilateral filtration (minutes)

% Darin Clark comments for teh brain
%For the reasons we discussed, I use the ?Median? variant of this filter. You, however, will likely want to use the ?Point? version (the standard definition of a bilateral filter). As a reminder, the ?Point? version will not do as good a job cleaning up noise around sharp (large intensity gradient) edges, whereas the ?Median? version will slightly blur high intensity regions into lower intensity regions.
%  
% Please note that these functions have several parameters hard-wired into them which are specially set up to deal with my CT data (ex. a 3x3x3x3  x,y,z,t window size, the standard deviations for the averaging and weighting components); these parameters may or may not be ideal for MRI data. Also note, at a certain point, I stopped updating the ?Point? version of the filter, such that it still requires a mask (this can be modified if you like what the filter does). It creates a rectangular ROI around the mask and only filters that portion of the volume. The ?Median? version assumes you want to filter everything.
%  
% * Call the ?Point? version of the function with three arguments: (files, mask, outname)
%  
% Files ? A cell array of strings referencing nifti volumes; the three files to use during the filtering process; the 2nd file is assumed to be the data to be corrected
%  
% Mask ? The mask to use to define the ROI to be filtered
%  
% Outname ? Path, name, and file extension (must be ?*.nii?) of the location to which to save the result
%  
% * Call the ?Median? version in a similar manner except without the mask argument: (files, outname)
%  
% Also note, you will need the nifiti functions included in your Matlab system path (e.g. make_nii, save_nii, etc.).
%  
% This will take 10+ minutes to run on your larger volumes and require a fair amount of system RAM. This code is not parallel (unfortunately).
%  
% Alex Badea comments: add reference to paper


    sigma_d = 21828.2685;
    sigma_r = 115.511;
    w = 1;

    estimate1 = load_nii(files{1});
    estimate2 = load_nii(files{2}); % the file to be corrected
    estimate3 = load_nii(files{3});

    estimate1 = estimate1.img;
    estimate2 = estimate2.img;
    estimate3 = estimate3.img;

    xsize = size(estimate2,1); ysize = size(estimate2,2); zsize = size(estimate2,3);

    estimates = zeros(xsize,ysize,zsize,3);
    estimates(:,:,:,1) = estimate1;
    estimates(:,:,:,2) = estimate2;
    estimates(:,:,:,3) = estimate3;

    clear estimate1 estimate2 estimate3;

    % Determine the appropriate filtering range using the mask

    mask_vol = load_nii(mask);

    mask_vol = double(mask_vol.img);

    masked_volume = estimates(:,:,:,2).*mask_vol;

    xcrop = sum(sum(masked_volume, 3),2);
    xcrop = xcrop(:);
    ycrop = sum(sum(masked_volume, 3),1);
    ycrop = ycrop(:);
    zcrop = sum(sum(masked_volume, 1),2);
    zcrop = zcrop(:);

    firstx = find(xcrop ~= 0, 1, 'first');
    lastx = find(xcrop ~= 0, 1, 'last');
    firsty = find(ycrop ~= 0, 1, 'first');
    lasty = find(ycrop ~= 0, 1, 'last');
    firstz = find(zcrop ~= 0, 1, 'first');
    lastz = find(zcrop ~= 0, 1, 'last');

    clear xcrop ycrop zcrop;
    
    wsize = 2*w+1;
        
    [X,Y,Z] = meshgrid(-w:w,-w:w,-w:w);
    X = X/w; Y = Y/w; Z = Z/w;

    X2 = zeros(wsize,wsize,wsize,wsize); Y2 = zeros(wsize,wsize,wsize,wsize); Z2 = zeros(wsize,wsize,wsize,wsize);
    
    space = linspace(-1,1,wsize);
    T = zeros(wsize,wsize,wsize,wsize);
    
    % Build the 4th dimension
    for i = 1:wsize

        X2(:,:,:,i) = X;
        Y2(:,:,:,i) = Y;
        Z2(:,:,:,i) = Z;
        T(:,:,:,i) = space(i)*ones(wsize,wsize,wsize);
    
    end
    
    G = exp(-(X2.^2+Y2.^2+Z2.^2+T.^2)/(2*sigma_d^2)); % 4D Gaussian => distance bias

    % Use phase 2 as the initial estimate
    B = estimates(:,:,:,2);
    constant = -1/(2*sigma_r^2);

    tMin = 2 - w;
    tMax = 2 + w;

    for i = firstx:lastx % rows
        for j = firsty:lasty % columns
            for g = firstz:lastz % slices

                % Adaptive filter size
                iMin = max(i-w,1);
                iMax = min(i+w,xsize);
                jMin = max(j-w,1);
                jMax = min(j+w,ysize);
                gMin = max(g-w,1);
                gMax = min(g+w,zsize);
                I = estimates(iMin:iMax,jMin:jMax,gMin:gMax,tMin:tMax);

                % Range
                H = zeros(numel(iMin:iMax),numel(jMin:jMax),numel(gMin:gMax),numel(tMin:tMax));
                mid = estimates(i,j,g,2);

                difference = I(:,:,:,:) - mid;
                H(:,:,:,:) = exp(constant*(difference.^2));  % 4D Gaussian => variance bias

                % Bilateral Filtration
                F = H.*G((iMin:iMax)-i+w+1,(jMin:jMax)-j+w+1,(gMin:gMax)-g+w+1,:);
                norm_F = sum(F(:));

                B(i,j,g) = sum(sum(sum(sum(F.*I))))./norm_F;

            end
        end
    end

    nii = make_nii(B, [0.088 0.088 0.088], [-0.088 -0.088 0.088], 16);
    save_nii(nii, outname);
    % copy_header(files{2},outname);

end

