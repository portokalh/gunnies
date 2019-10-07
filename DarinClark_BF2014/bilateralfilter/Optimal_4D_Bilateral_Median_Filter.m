function [ ] = Optimal_4D_Bilateral_Median_Filter(files, outname)
% Optimal_4D_Bilateral_Median_Filter
%   Input 1 - files: three files to be used for filtering the middle file
%   Input 2 - outname: path and name of the generated, filtered file

    % These parameters were originally optimized for registered data
    % using the median variant
    sigma_d = 7264.8;
    sigma_r = 79.1737;
    w = 1;
    wsize = 2*w+1;

    estimate1 = load_nii(files{1});
    estimate2 = load_nii(files{2}); % the file to be corrected
    estimate3 = load_nii(files{3});

    estimate1 = estimate1.img;
    estimate2 = estimate2.img;
    estimate3 = estimate3.img;

    [xsize ysize zsize] = size(estimate2);

    estimates = zeros(xsize,ysize,zsize,wsize);
    estimates(:,:,:,1) = estimate1;
    estimates(:,:,:,2) = estimate2;
    estimates(:,:,:,3) = estimate3;

    clear estimate1 estimate2 estimate3;
        
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
    
    % temp = single(zeros(xsize, ysize, zsize, 3, 3, 3, 3));

    for i = 1:xsize % rows
        for j = 1:ysize % columns
            for g = 1:zsize % slices

                % Adaptive filter size
                iMin = max(i-w,1);
                iMax = min(i+w,xsize);
                jMin = max(j-w,1);
                jMax = min(j+w,ysize);
                gMin = max(g-w,1);
                gMax = min(g+w,zsize);
                I = estimates(iMin:iMax,jMin:jMax,gMin:gMax,:);

                % Range
                H = zeros(numel(iMin:iMax),numel(jMin:jMax),numel(gMin:gMax),wsize);
                med = median(I(:));

                difference = I(:,:,:,:) - med;
                H(:,:,:,:) = exp(constant*(difference.^2));  % 4D Gaussian => variance bias

                % Bilateral Filtration
                F = H.*G((iMin:iMax)-i+w+1,(jMin:jMax)-j+w+1,(gMin:gMax)-g+w+1,:);
                % temp(i,j,g,1:numel(iMin:iMax),1:numel(jMin:jMax),1:numel(gMin:gMax),:) = F;
                norm_F = sum(F(:));

                B(i,j,g) = sum(sum(sum(sum(F.*I))))./norm_F;

            end
        end
    end

    nii = make_nii(B, [0.088 0.088 0.088], [-0.088 -0.088 0.088], 16);
    save_nii(nii, outname);
    % copy_header(files{2},outname);

end

